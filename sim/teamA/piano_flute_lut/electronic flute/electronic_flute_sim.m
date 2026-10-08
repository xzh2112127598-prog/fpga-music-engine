%% electronic_flute_sim.m
% =========================================================================
% 电子笛子音频算法 MATLAB 仿真
% 项目: 嵌入式芯片设计大赛 —— 基于高云 Tang25K FPGA 的电子笛子
% 硬件: 6 路触摸音孔 + 气流传感器 -> FPGA 实时合成 -> ES8388 (I2S) -> 喇叭
%
% 算法内容:
%   1) 指法查表 : 6bit 指法编码 -> 音名/基频 (筒音作5, D调, 一个八度 8 音)
%   2) 波形合成 : 基波 + 2 次谐波 + 3 次谐波叠加, 模拟笛子音色
%   3) 气声模拟 : 气流强度 -> 音量包络(非线性) + 高频气声噪声(带通白噪声)
%   4) 播放导出 : audioplayer 实时播放 + audiowrite 导出 16bit/48kHz WAV
%
% 运行: 直接按 F5, 依次听到 5 6 7 1 2 3 4 5^ (一个八度音阶上行)
% 移植: 各参数集中在文件头, 与 Verilog parameter 一一对应; 合成采用
%       相位累加(DDS) + 谐波叠加, 天然适合 FPGA 定点实现
% =========================================================================
clear; clc; close all;
rng(2026);          % 固定随机种子, 使气声噪声可复现, 便于调试对比

%% ============ 1. 系统参数 (对应 Verilog parameter) ============
Fs         = 48000;               % 采样率 Hz, 与 ES8388 I2S 一致
A1         = 1.00;                % 基波幅度系数
A2         = 0.50;                % 2 次谐波幅度系数
A3         = 0.30;                % 3 次谐波幅度系数
NOISE_GAIN = 0.05;                % 气声噪声增益 (相对满幅 1.0)
NOISE_BAND = [1500 6000];         % 气声噪声频带 Hz (笛子气声偏中高频)
VIB_RATE   = 5.5;                 % 颤音频率 Hz (0=关闭)
VIB_DEPTH  = 0.004;               % 颤音深度 (相对基频, 0=关闭)
RUN_PLAYBACK = true;              % true=播放, false=只计算/绘图/导出

%% ============ 2. 指法查表 (筒音作5, D调六孔) ============
% 指法编码: 6 位字符串 'b1b2b3b4b5b6'
%   bi = 1 -> 第 i 孔打开(手指抬起), bi = 0 -> 第 i 孔闭合(手指按住)
%   孔序: 1 号孔最靠近吹孔, 6 号孔最靠近尾端 (硬件映射可自行调整)
% 频率: 十二平均律, A4 = 440 Hz, f = 440 * 2^((midi-69)/12)
ft(1)  = struct('fing','000000','jianpu','5','name','D5','f0',587.33,'overblow',0);
ft(2)  = struct('fing','100000','jianpu','6','name','E5','f0',659.26,'overblow',0);
ft(3)  = struct('fing','110000','jianpu','7','name','F#5','f0',739.99,'overblow',0);
ft(4)  = struct('fing','111000','jianpu','1','name','G5','f0',783.99,'overblow',0);
ft(5)  = struct('fing','111100','jianpu','2','name','A5','f0',880.00,'overblow',0);
ft(6)  = struct('fing','111110','jianpu','3','name','B5','f0',987.77,'overblow',0);
ft(7)  = struct('fing','111111','jianpu','4','name','C6','f0',1046.50,'overblow',0);
ft(8)  = struct('fing','000000','jianpu','5^','name','D6','f0',1174.66,'overblow',1); % 全按超吹

fprintf('=== 指法查表 (筒音作5, D调, 6孔) ===\n');
fprintf(' 简谱   音名    频率Hz    指法(1-6孔)   备注\n');
for k = 1:numel(ft)
    tag = ''; if ft(k).overblow, tag = '超吹'; end
    fprintf('  %-4s  %-5s  %8.2f    %s       %s\n', ...
        ft(k).jianpu, ft(k).name, ft(k).f0, ft(k).fing, tag);
end

%% ============ 3. 演示乐谱: 一个八度音阶上行 ============
% 每行: {指法(6bit), 超吹标志, 时长s, 气流强度(0~1)}
score = {
    '000000', 0, 0.40, 0.85;   % 5
    '100000', 0, 0.40, 0.85;   % 6
    '110000', 0, 0.40, 0.85;   % 7
    '111000', 0, 0.40, 0.85;   % 1
    '111100', 0, 0.40, 0.85;   % 2
    '111110', 0, 0.40, 0.85;   % 3
    '111111', 0, 0.40, 0.85;   % 4
    '000000', 1, 0.55, 1.00;   % 5^ (超吹, 气流更强)
    };
GAP = 0.030;    % 音符间静音 s (模拟吐音断开)
ATT = 0.060;    % 起音时间 s
REL = 0.100;    % 收音时间 s

%% ============ 4. 逐音符合成 ============
y_all      = [];      % 整曲波形
breath_all = [];      % 整曲气流包络 (绘图用)
note_mark  = [];      % 每个音符的起始采样点
note_label = {};      % 音符标签

for k = 1:size(score,1)
    fing  = score{k,1};
    ob    = score{k,2};
    dur   = score{k,3};
    level = score{k,4};

    % 4.1 指法查表 -> 基频
    [f0, jp] = fingering_lookup(ft, fing, ob);

    % 4.2 气流包络 (模拟气流传感器输出; 有实测数据时可替换)
    breath = breath_profile(Fs, dur, level, ATT, REL);

    % 4.3 谐波合成: 基波 + 2次 + 3次谐波
    P = struct('A1',A1,'A2',A2,'A3',A3, ...
               'vib_rate',VIB_RATE,'vib_depth',VIB_DEPTH,'overblow',ob);
    y_note = synth_flute_tone(Fs, f0, breath, P);

    % 4.4 气声噪声: 带通白噪声, 由气流强度调制
    noise  = synth_breath_noise(Fs, numel(breath), breath, NOISE_GAIN, NOISE_BAND);

    x = y_note + noise;          % 笛音 + 气声

    % 4.5 拼接 (音符间加静音, 模拟吐音)
    L0 = numel(y_all);
    g  = zeros(1, round(GAP*Fs));
    y_all      = [y_all, x, g];
    breath_all = [breath_all, breath, zeros(1, numel(g))];
    note_mark  = [note_mark, L0+1];
    note_label{end+1} = jp;
end

t_all = (0:numel(y_all)-1)/Fs;                              % 整曲时间轴
y_all = 0.9 * y_all / (max(abs(y_all)) + eps);              % 归一化防削波

fprintf('\n整曲时长 %.2fs, 采样点数 %d, 峰值 %.2f\n', ...
    numel(y_all)/Fs, numel(y_all), max(abs(y_all)));

%% ============ 5. 可视化 ============
% ---- 图1: 指法-频率对照 ----
figure('Name','指法-频率对照','Position',[60 60 900 400]);
stem(1:numel(ft), [ft.f0], 'filled','LineWidth',1.6,'Color',[0.00 0.45 0.75]);
hold on; grid on;
for k = 1:numel(ft)
    text(k, ft(k).f0+28, sprintf('%s\n%s', ft(k).jianpu, ft(k).fing), ...
        'HorizontalAlignment','center','FontSize',9,'Interpreter','none');
end
set(gca,'XTick',1:numel(ft),'XTickLabel',{ft.jianpu},'TickLabelInterpreter','none');
ylabel('基频 f0 (Hz)'); xlabel('音阶 (筒音作5)');
title('指法查表: 一个八度 8 音基频分布');

% ---- 图2: 第一个音符的音色/包络/频谱分解 ----
gapS   = round(GAP*Fs);
n1     = note_mark(1);
seg_end = note_mark(2) - gapS - 1;      % 第一个音符(不含尾静音)
x1 = y_all(n1:seg_end);
b1 = breath_all(n1:seg_end);
t1 = (0:numel(x1)-1)/Fs;

figure('Name','单音分解','Position',[60 480 900 460]);
subplot(3,1,1);
plot(t1, b1, 'Color',[0.85 0.33 0.10],'LineWidth',1.2); grid on;
ylabel('气流'); xlim([0 t1(end)]);
title('气流包络 (控制音量与气声)');
subplot(3,1,2);
plot(t1, x1, 'Color',[0.00 0.45 0.75]); grid on;
ylabel('幅值'); xlim([0 t1(end)]);
title('谐波合成波形 (基波+2/3次谐波+气声)');
subplot(3,1,3);
Nw = numel(x1);
w  = 0.5*(1 - cos(2*pi*(0:Nw-1)/(Nw-1)));      % Hann 窗(免工具箱)
X  = fft(x1 .* w);
f  = (0:Nw-1)/Nw*Fs;
mag = abs(X); mag = mag/max(mag);
plot(f, 20*log10(mag+eps), 'Color',[0.30 0.30 0.30]); grid on;
xlim([0 8000]); ylim([-80 5]);
xlabel('频率 (Hz)'); ylabel('dB'); title('单音频谱 (红点为1/2/3次谐波)');
hold on;
for h = 1:3
    [~, idx] = min(abs(f - h*ft(1).f0));
    stem(f(idx), 20*log10(mag(idx)+eps), 'r','LineWidth',1.2);
    text(f(idx)+80, 20*log10(mag(idx)+eps), sprintf('%d次 %.0fHz',h,f(idx)), ...
        'Color','r','FontSize',8);
end

% ---- 音频自检: 实测谐波频率与幅度比 ----
% 补零FFT提高频率分辨率; 谐波±40Hz带内幅度求和, 抵消颤音展宽的影响
f_peak = zeros(1,3); a_peak = zeros(1,3);
exp_ratio = [1 0.5 0.3];                 % 期望幅度比 (基波:2次:3次)
Nfft = 2^nextpow2(Nw)*4;
Xp = fft(x1 .* w, Nfft);
fp = (0:Nfft-1)/Nfft*Fs;
magp = abs(Xp);
for h = 1:3
    win = (fp >= h*ft(1).f0-40) & (fp <= h*ft(1).f0+40);
    a_peak(h) = sum(magp(win));          % 带内幅度和(比峰值测量更稳)
    fi = find(win);
    [~, pk] = max(magp(win));
    f_peak(h) = fp(fi(pk));
end
fprintf('\n=== 音频自检 (第一音 5/D5, 期望幅度比 1:0.50:0.30) ===\n');
fprintf(' 谐波   理论Hz     实测Hz    幅度比(实测)   期望比\n');
for h = 1:3
    fprintf(' %d次   %7.2f   %7.2f     %.3f        %.2f\n', ...
        h, h*ft(1).f0, f_peak(h), a_peak(h)/a_peak(1), exp_ratio(h));
end

% ---- 图3: 整曲波形 + 音符边界 ----
figure('Name','整曲波形','Position',[60 960 1000 300]);
plot(t_all, y_all, 'Color',[0.00 0.45 0.75]); grid on; hold on;
ylim([-1.1 1.1]);
for k = 1:numel(note_mark)
    ts = (note_mark(k)-1)/Fs;
    line([ts ts], [-1 1], 'Color',[0.85 0.25 0.25],'LineStyle','--');
    text(ts, 0.95, note_label{k}, 'Color',[0.85 0.25 0.25],'FontSize',10, ...
        'Interpreter','none');
end
xlabel('时间 (s)'); ylabel('幅值');
title('八度音阶整曲波形 (吐音断开, 虚线为音符边界)');

% ---- 图4: 语谱图 ----
try
    figure('Name','语谱图','Position',[60 1280 1000 340]);
    spectrogram(y_all, 1024, 512, 2048, Fs, 'yaxis');
    title('整曲语谱图 (三根横线=基波/2次/3次谐波, 高频散点=气声)');
catch
    warning('语谱图需要 Signal Processing Toolbox, 已跳过图4');
end

%% ============ 6. 播放与导出 ============
if RUN_PLAYBACK
    try
        p = audioplayer(y_all, Fs);
        playblocking(p);        % 阻塞直到播完, 避免脚本结束时被中断
    catch
        try
            soundsc(y_all, Fs);
        catch ME
            warning('无法播放音频: %s', ME.message);
        end
    end
end

out_dir = fileparts(mfilename('fullpath'));
if isempty(out_dir), out_dir = pwd; end
wav_path = fullfile(out_dir, 'electronic_flute_scale.wav');
try
    audiowrite(wav_path, y_all, Fs);
    fprintf('\n已导出: %s (%.2fs, %dHz, 16bit)\n', wav_path, numel(y_all)/Fs, Fs);
catch ME
    warning('导出 WAV 失败: %s', ME.message);
end

%% =================== 局部函数 ===================
function [f0, jianpu] = fingering_lookup(ft, fing, overblow)
% 指法查表: 顺序查找, 等价于 Verilog 的 case 语句 / ROM 查表
for k = 1:numel(ft)
    if strcmp(ft(k).fing, fing) && ft(k).overblow == overblow
        f0 = ft(k).f0;
        jianpu = ft(k).jianpu;
        return;
    end
end
error('指法表未找到: fing=%s, overblow=%d', fing, overblow);
end

function env = breath_profile(Fs, dur, level, att, rel)
% 气流包络: 起音-保持-收音 (模拟气流传感器输出 -> 音量)
% 实际硬件调试时, 可直接用气流 ADC 实测波形替换本函数输出
n  = max(1, round(dur*Fs));
na = max(1, round(att*Fs));
nr = max(1, round(rel*Fs));
ns = max(0, n - na - nr);
env = [linspace(0,1,na), ones(1,ns), linspace(1,0,nr)];
env = env(1:n);
env = level * env(:).';
end

function y = synth_flute_tone(Fs, f0, breath, P)
% 笛子音色: 基波 + 2次谐波 + 3次谐波, 幅度由气流包络控制
% 超吹(高音5^)时增强高次谐波占比, 音色更亮
n = numel(breath);
t = (0:n-1)/Fs;
if P.overblow
    amps = [1.0, 0.60, 0.40];      % 超吹: 泛音更丰富
else
    amps = [P.A1, P.A2, P.A3];
end
if P.vib_rate > 0 && P.vib_depth > 0
    inst_f = f0 * (1 + P.vib_depth*sin(2*pi*P.vib_rate*t));   % 可选颤音
else
    inst_f = f0 * ones(1,n);
end
phase = 2*pi*cumsum(inst_f)/Fs;    % 相位累加 (对应 FPGA DDS 相位累加器)
y = amps(1)*sin(phase) + amps(2)*sin(2*phase) + amps(3)*sin(3*phase);
y = y .* (breath.^1.2) / sum(amps);   % 气流->音量(非线性), 并归一化
end

function noise = synth_breath_noise(Fs, n, breath, gain, band)
% 气声模拟: 白噪声 -> 带通滤波(1.5k~6k) -> 气流强度调制
% 气流越强气声越大; 起音瞬间额外加强, 模拟真实笛子的"呼"声
if gain <= 0 || n < 16
    noise = zeros(1,n);
    return;
end
[b, a] = butter(4, band/(Fs/2), 'bandpass');
noise  = filter(b, a, randn(1,n));
env    = breath.^2;                        % 气声与气流近似平方关系
na     = min(n, round(0.05*Fs));           % 起音 50ms 气声增强
if na > 1
    env = env .* [linspace(2.5,1,na), ones(1,n-na)];
end
noise = gain * (noise .* env) / (max(abs(noise)) + eps);
end
