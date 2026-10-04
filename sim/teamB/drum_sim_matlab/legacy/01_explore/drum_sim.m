%% =========================================================
%  鼓槌 MATLAB 仿真：敲击检测 + 鼓件分区 + 鼓音色合成
%  对应硬件：MPU6050(加速度+陀螺仪) -> 检测器 -> 振荡器合成 -> I2S
%  运行：直接 F5；最终会听到 3 次敲击（底鼓/军鼓/镲）
%  =========================================================
clear; clc; close all; rng(0);
Fs       = 48000;      % 音频采样率
IMU_RATE = 1000;       % IMU 采样率 1kHz（MPU6050 可配）
g        = 9.8;

%% ========== Part A：模拟鼓槌三轴加速度（真实数据以后用 UART 录回来替换） ==========
dur = 1.5;
tt  = (0:1/IMU_RATE:dur-1/IMU_RATE)';
ax = zeros(size(tt));
ay = zeros(size(tt));
az = ones(size(tt))*g;          % 静止：z 轴 = 1g

% 三次敲击：[时刻s, 方向(-1左斜 0正中 1右斜), 强度g]
hits = [0.30  0  9;
        0.70 -1  6;
        1.10  1  4];
for k = 1:size(hits,1)
    tk = hits(k,1); dirc = hits(k,2); strength = hits(k,3);
    idx = abs(tt-tk) < 0.012;
    pulse = strength*exp(-((tt(idx)-tk)/0.004).^2)*g;  % 高斯形减速尖峰
    kd = 0.5*abs(dirc);                                % 斜击分量比例
    az(idx) = az(idx) - pulse*(1-kd);                  % 下砸分量
    ay(idx) = ay(idx) - dirc*pulse*kd;                 % 左斜为正、右斜为负
end
% !!硬件提醒：MPU6050 量程必须配 ±16g（寄存器0x1C），默认 ±2g 一击爆表
% 量化模拟（可选，±16g 下灵敏度 2048 LSB/g）：
% lsb = round(ax/16*32768);

%% ========== Part B：敲击检测状态机（IDLE->峰值跟踪->不应期） ==========
THR   = 0.5*g;            % 动作阈值
WIN   = 0.005;            % 峰值跟踪窗口 5ms
REFR  = 0.10;             % 不应期 100ms
state = 0; peak = 0; wcnt = 0; lastfire = -1; ay_sum = 0;
events = [];              % [时刻, 鼓件(1底鼓2军鼓3镲), 力度0~127]

for i = 1:length(tt)
    dz = az(i)-g;
    amag = sqrt(ax(i)^2 + ay(i)^2 + dz^2);   % 去重力合幅（平方和）
    switch state
        case 0   % IDLE
            if amag > THR && tt(i)-lastfire > REFR
                state = 1; peak = amag; wcnt = 0; ay_sum = 0;
            end
        case 1   % TRACK：跟踪峰值 + 累计方向
            peak = max(peak, amag); ay_sum = ay_sum + ay(i); wcnt = wcnt+1;
            if wcnt > WIN*IMU_RATE
                dir_mean = ay_sum/wcnt;
                if dir_mean >  0.3*g, drum = 2;          % 左斜 -> 军鼓
                elseif dir_mean < -0.3*g, drum = 3;      % 右斜 -> 镲
                else, drum = 1; end                     % 正中 -> 底鼓
                vel = min(127, round(peak/(10*g)*127));
                events = [events; tt(i), drum, vel];
                state = 2; lastfire = tt(i);
            end
        case 2   % REFRACTORY
            if tt(i)-lastfire > REFR, state = 0; end
    end
end
disp('检测到的事件 [时刻 鼓件 力度]：'); disp(events);

%% ========== Part C：按事件合成并贴到主轨道 ==========
audio = zeros(round(Fs*dur),1);
for e = 1:size(events,1)
    t0 = events(e,1); drum = events(e,2); vel = events(e,3)/127;
    switch drum
        case 1, s = kick(Fs);
        case 2, s = snare(Fs);
        case 3, s = hihat(Fs);
    end
    idx = round(t0*Fs) + (1:length(s));
    idx = idx(idx <= length(audio));
    audio(idx) = audio(idx) + s(1:length(idx))*vel;
end
audio = audio/max(abs(audio))*0.9;        % 归一化防爆音
audio_int16 = int16(audio*32767);        % 最终 int16 格式
sound(double(audio_int16)/32767, Fs);  % sound 只接受浮点；int16 保留供导出

% 导出测试向量：硬件仿真时作为“检测器输出”的标准答案
writematrix(events,'drum_events_golden.txt','Delimiter','\t');

%% ========== Part D：波形查看（也可在此对照真实鼓录音的频谱） ==========
figure;
subplot(2,1,1); plot(tt,az); xlabel('时间(s)'); ylabel('az (m/s^2)'); title('鼓槌 z 轴加速度（敲击尖峰）');
subplot(2,1,2); plot((0:length(audio)-1)/Fs,audio); xlabel('时间(s)'); title('合成鼓声音频');

%% =========================================================
%  本地函数（必须放在脚本末尾）
%  =========================================================
% ---- 底鼓：正弦频率 150->40Hz 快速下滑 + 快衰减 ----
function y = kick(Fs)
    d = 0.25; t = (0:1/Fs:d)';
    f = 150*exp(-t/0.02) + 40;
    phase = cumsum(f)/Fs;
    y = sin(2*pi*phase) .* exp(-t/0.15);
end

% ---- 军鼓：180/200Hz 音身 + 高通(差分)白噪声 ----
function y = snare(Fs)
    d = 0.18; t = (0:1/Fs:d)';
    body = 0.5*sin(2*pi*180*t) + 0.3*sin(2*pi*200*t);
    n = randn(length(t)+1,1);
    nh = diff(n);                       % 一阶差分≈高通
    y = body.*exp(-t/0.09)*0.6 + nh(1:length(t)).*exp(-t/0.07)*0.8;
end

% ---- 镲：三阶差分噪声(高频提亮) + 极短衰减 ----
function y = hihat(Fs)
    d = 0.10; t = (0:1/Fs:d)';
    n = randn(length(t)+3,1);
    nh = diff(diff(diff(n)));           % 三阶高通
    y = nh(1:length(t)).*exp(-t/0.05);
end
