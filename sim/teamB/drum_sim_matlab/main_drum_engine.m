%% =========================================================
%  芯上乐府 · FPGA 对齐定点黄金模型（P2：真实感增强）
%  32bit 频率字 / 3 谐波钢琴 / 鼓增强 / 混响 / 李萨如+频谱 /
%  32 声部 / 饱和加法树 / 力度曲线 / 延迟统计 / 黄金向量
%  运行：F5；输出 params、audio、fig、golden、docs
%  =========================================================
clear; clc; close all;
addpath('lib');
Fs = 48000;
rng(20251005);

%% ========== Part 0：参数与 ROM（唯一参数源 lib/init_engine.m）==========
%  改参数请改 init_engine.m，不要再在本文件里写死 —— 24bit/32bit 事故的根因
[P, sine_rom, noise_rom] = init_engine('params');
PB = P.pb;                            % 相位位宽（队长口径 32bit）
fprintf('[Part0] Fs=%d 相位位宽=%d FTW=round(f*2^%d/%d)\n', Fs, PB, PB, Fs);
% 以上参数全部来自 init_engine.m，此处不再重复定义

%% ========== Part 1：模块自测 + 黄金向量 ==========
[y440,~] = dds_render(sine_rom, Fs, ftw_calc(440,PB,Fs), 0, PB);
ref440 = round(sin(2*pi*440*(0:Fs-1)'/Fs)*32767);
err = y440 - ref440;
fprintf('DDS440 最大误差 %d LSB, |err|>1 样本 %d / %d\n', max(abs(err)), sum(abs(err)>1), Fs);
writematrix(y440,'golden/dds_440_out.txt');
[y440ip,~] = dds_render_ip(sine_rom, Fs, ftw_calc(440,PB,Fs), 0, PB);
errip = y440ip - ref440;
fprintf('插值DDS440 最大误差 %d LSB, |err|>1 样本 %d / %d\n', max(abs(errip)), sum(abs(errip)>1), Fs);
writematrix(y440ip,'golden/dds_440_ip_out.txt');
yn = dds_render(noise_rom, round(0.5*Fs), P.noise_ftw, 0, PB);
writematrix(yn,'golden/noise_out.txt');
fprintf('噪声: 均值 %.1f, RMS %.0f\n', mean(yn), sqrt(mean(yn.^2)));
vct = vel_curve(0.8);
writematrix(vct,'golden/vel_curve.txt');

%% ========== Part 2：32 声部分配器压力测试 ==========
V = voice_init(32);
active = zeros(400,1); steals = 0;
for k = 1:400
    note = randi([48,72]);
    if rand < 0.7
        [V,ch] = voice_noteon(V, note, 20000, randi(4));
        if V(ch).age == 0 && sum([V.state]>0) == 32, steals = steals+1; end
        if rand < 0.3, V = voice_noteoff(V, note); end
    else, V = voice_noteoff(V, note); end
    active(k) = sum([V.state] > 0);
end
fprintf('声部分配: 400 事件，峰值并发 %d，窃取 %d\n', max(active), steals);

%% ========== Part 3：系统级仿真（IMU 定点检测 -> 32声部）==========
LSBg = 2048; IMU_RATE = 1000; dur = 2.8;
tt = (0:1/IMU_RATE:dur-1/IMU_RATE)';
ax = zeros(size(tt)); ay = zeros(size(tt)); az = ones(size(tt))*LSBg;
hits = [0.30 0 9; 0.70 -1 6; 1.10 1 4; 1.40 0 7;
        1.70 -1 5; 2.00 1 3; 2.20 0 8; 2.40 0 4];
for k = 1:size(hits,1)
    tk=hits(k,1); dirc=hits(k,2); strength=hits(k,3);
    idx = abs(tt-tk) < 0.012;
    pulse = strength*exp(-((tt(idx)-tk)/0.004).^2)*LSBg;
    kd = 0.5*abs(dirc);
    az(idx) = az(idx) - pulse*(1-kd);
    ay(idx) = ay(idx) - dirc*pulse*kd;
end
ax = round(ax); ay = round(ay); az = round(az);
THR_SQ   = (LSBg/2)^2;                       % 比平方，不开根号（与 RTL 一致）
WIN_CNT  = 5*IMU_RATE/1000 + 1;              % =6，MATLAB 判据 wcnt>WIN*IMU_RATE 即 wcnt>=6
REFR_CNT = 100*IMU_RATE/1000;                % =100
VEL_K    = floor(127*65536/(10*LSBg));       % Q16 力度系数，与 RTL 的 localparam 一致
DIR_TH_NUM = ceil(0.3*LSBg*WIN_CNT);         % 方位判据的分子版，避免整除边界差一
state=0; peak_sq=0; wcnt=0; lastfire=-inf; ays=0; events=[]; hitstart=0;
% 重力基线：慢速平均 base += floor((cur-base)/32)（即 RTL 的 >>>5）
% 上电第一个样本直接预置（RTL 的 primed），否则 base 从 0 爬到 1g 期间会连续误触发
bx=ax(1); by=ay(1); bz=az(1);
for i = 1:length(tt)
    if i == 1, dx=0; dy=0; dz=0;             % 预置样本不参与检测
    else,      dx=ax(i)-bx; dy=ay(i)-by; dz=az(i)-bz; end
    magsq = dx^2 + dy^2 + dz^2;              % 与 RTL 的 40bit 平方和一致
    switch state
        case 0
            if magsq>THR_SQ && (i-lastfire)>REFR_CNT
                state=1; peak_sq=magsq; wcnt=0; ays=0; hitstart=tt(i);
            end
        case 1
            peak_sq=max(peak_sq,magsq); ays=ays+dy; wcnt=wcnt+1;
            if wcnt >= WIN_CNT
                if      ays >=  DIR_TH_NUM, type=2;
                elseif  ays <= -DIR_TH_NUM, type=3;
                else,                       type=1; end
                peak = floor(sqrt(peak_sq));              % RTL isqrt 是向下取整
                rawv = min(127, floor(peak*VEL_K/65536)); % 定点，与 RTL 的 >>16 一致
                events=[events; tt(i), hitstart, type, rawv];
                state=2; lastfire=i;
            end
        case 2
            if (i-lastfire)>=REFR_CNT, state=0; end   % >= 才与 RTL 的倒数计数同拍
    end
    bx = bx + floor((ax(i)-bx)/32);
    by = by + floor((ay(i)-by)/32);
    bz = bz + floor((az(i)-bz)/32);
end
disp('检测事件 [t_detect t_hitstart type rawvel]'); disp(events);
writematrix(events,'golden/imu_events.txt');
writematrix(az,'golden/imu_az.txt');
writematrix(ay,'golden/imu_ay.txt');

% ---- RTL testbench 用的十六进制版本（$readmemh 只认 hex）----
dump_hex('golden/imu_ax.hex', ax, 16);
dump_hex('golden/imu_ay.hex', ay, 16);
dump_hex('golden/imu_az.hex', az, 16);
% 期望事件：第 0 行=事件数，之后每行 = {索引[31:16], 类型[15:8], 力度[7:0]}
idx0 = round(events(:,1) * IMU_RATE);
fidg = fopen('golden/imu_expect.hex','w');
fprintf(fidg, '%08X\n', size(events,1));
for e = 1:size(events,1)
    fprintf(fidg, '%08X\n', ...
        bitshift(idx0(e),16) + bitshift(events(e,3),8) + events(e,4));
end
fclose(fidg);
fprintf('黄金向量（hex）已写出，共 %d 个期望事件\n', size(events,1));

pnotes = [60 62 64 65 67 69 71 72];
pev = zeros(length(pnotes),3);
for i = 1:length(pnotes)
    ton = 0.5 + (i-1)*0.25;
    pev(i,:) = [ton, ton+0.2, pnotes(i)];
end

V = voice_init(32);
T = round(dur*Fs);
ch = zeros(32,T);
eq = 1; pq = 1; lat_aud = zeros(size(events,1),1);
for n = 1:T
    tn = n/Fs;
    while eq <= size(events,1) && tn >= events(eq,1)
        vel = vct(events(eq,4)+1);
        vq = round(vel/127*32767);
        [V,cc] = voice_noteon(V, events(eq,3), vq, events(eq,3));
        lat_aud(eq) = n; eq = eq+1;
    end
    while pq <= size(pev,1) && tn >= pev(pq,1)
        f = 440*2^((pev(pq,3)-69)/12);
        [V, pc] = voice_noteon(V, pev(pq,3), round(100/127*32767), 4);
        V(pc).ftw = ftw_calc(f,PB,Fs);
        pq = pq+1;
    end
    for i = 1:size(pev,1)
        if pev(i,2) > 0 && tn >= pev(i,2)
            V = voice_noteoff(V, pev(i,3)); pev(i,2)=0;
        end
    end
    for k = 1:32
        [s, V(k)] = voice_render(V(k), struct('sine',sine_rom,'noise',noise_rom), P, 0);
        ch(k,n) = s;
    end
end
dry = round(mix_tree(ch)*0.85);
dry = dry(:);                              % 统一为列向量（mix_tree 输出 1×T）

%% ========== Part 4：混响（逐样本后处理）==========
rv = reverb_init();
wet_sig = zeros(T,1);
for n = 1:T
    [wet_sig(n), rv] = reverb_tick(dry(n), rv);
end
y = sat16(q15mul(dry,round(0.8*32768)) + q15mul(wet_sig,round(0.2*32768)));
audiowrite('audio/fpga_demo_mix.wav', int16(y), Fs);

nbad = 0; i0 = round(0.75*Fs);
for k = 1:32
    tail = ch(k, i0:end);
    if max(tail)-min(tail)==0 && tail(1)~=0, nbad = nbad+1; end
end
fprintf('系统输出: 峰值 %d, 削波 %d, 恒定异常声部 %d\n', max(abs(y)), sum(abs(y)>=32767), nbad);

%% ========== Part 5：延迟统计 ==========
lat = (lat_aud./Fs - events(:,2))*1000;
figure('Name','延迟分布'); histogram(lat,12); grid on;
xlabel('端到端延迟 (ms)'); title('鼓槌端到端延迟（含5ms峰值窗口）');
fprintf('延迟: 平均 %.2f ms, 最大 %.2f ms\n', mean(lat), max(lat));

%% ========== Part 6：李萨如可视化（不同音程）==========
tl = 0:1/Fs:0.5;
ratios = [2 1; 3 2; 5 4];
names_l = {'八度 2:1','五度 3:2','大三度 5:4'};
figure('Name','李萨如');
for k = 1:3
    subplot(1,3,k);
    X = sin(2*pi*440*tl);
    Y = sin(2*pi*440*ratios(k,1)/ratios(k,2)*tl + pi/2);
    plot(X,Y); axis equal; title(names_l{k}); grid on;
end
print(gcf,'fig/lissajous.png','-dpng','-r120');

%% ========== Part 7：频谱可视化 ==========
figure('Name','输出频谱');
i1 = round(1.7*Fs); i2 = round(1.9*Fs);
seg = y(i1:i2).*hann(i2-i1+1);
X = abs(fft(seg)); fv = (0:length(X)-1)*Fs/length(X);
nhalf = floor(length(X)/2);
plot(fv(1:nhalf), X(1:nhalf)); xlim([0 6000]); grid on;
xlabel('频率Hz'); title('系统输出频谱（鼓+钢琴齐鸣段）');
print(gcf,'fig/spectrum.png','-dpng','-r120');

figure('Name','系统输出');
tp=(0:T-1)/Fs; plot(tp,y); hold on;
plot(events(:,2),0,'r^','MarkerFaceColor','r');
xlabel('时间(s)'); title('系统输出（含混响，三角=敲击）'); grid on;
print(gcf,'fig/fpga_demo_mix.png','-dpng','-r150');

%% ========== 验证报告 ==========
fid = fopen('docs/verify_report.txt','w');
fprintf(fid,'P2 定点黄金模型验证报告（真实感增强）\n\n');
fprintf(fid,'[配置] 32bit频率字 / 48kHz / Q15 / 正弦1024 噪声8192\n\n');
fprintf(fid,'[P0] 无插值DDS误差 %d LSB；插值DDS误差 %d LSB\n', max(abs(err)), max(abs(errip)));
fprintf(fid,'     LFSR噪声 RMS %.0f（理论18919）\n', sqrt(mean(yn.^2)));
fprintf(fid,'[P1] 32声部 峰值并发%d 窃取%d；饱和加法树 峰值%d 削波%d\n', max(active), steals, max(abs(y)), sum(abs(y)>=32767));
fprintf(fid,'     端到端延迟 平均%.2f 最大%.2f ms（指标10ms）\n', mean(lat), max(lat));
fprintf(fid,'[P2] 钢琴3谐波(1:0.35:0.12)+独立包络(1.2/0.6/0.3s)\n');
fprintf(fid,'     鼓增强(kick click/响弦5-9k/镲金属共振)；Freeverb混响\n');
fprintf(fid,'     李萨如+频谱可视化；恒定异常声部 %d\n', nbad);
fclose(fid);
disp('=== P2 全部完成：见 docs/verify_report.txt ===');

function dump_hex(fname, data, width)
% DUMP_HEX 导出十六进制补码向量，供 Verilog $readmemh 读取
d = round(data(:));
d = mod(d, 2^width);                  % 负数转补码
fid = fopen(fname, 'w');
ndig = ceil(width/4);
for i = 1:length(d)
    fprintf(fid, '%0*X\n', ndig, d(i));
end
fclose(fid);
end

