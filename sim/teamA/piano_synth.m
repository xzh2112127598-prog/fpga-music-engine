%% piano_synth.m —— 钢琴单音合成（加法合成）
%  用途：在电脑上先"算出"钢琴音，确认音色正确，供 FPGA 参考。
%  用法：MATLAB 里双击打开，按 F5 运行。
%  输出：demo_piano.wav（12 个音连播）、single_C4.wav（单音）、piano_plots.png（波形+频谱图）
clear; clc; close all;

fs = 48000;                                   % 采样率 48kHz（与 FPGA 保持一致，重要！）
notes = [60 62 64 65 67 69 71 72 74 76 77 79]; % 12 个音：C4 开始的大调音阶（MIDI 编号）
t_all = [];                                   % 用来拼"12 音演示文件"
x1 = []; f1 = 0;                              % 留第一个音（C4）画图用

for n = 1:length(notes)
    midi = notes(n);
    f0 = 440 * 2^((midi - 69) / 12);          % MIDI 编号 → 频率（A4=440Hz 十二平均律）
    dur = 2.0;                                % 每个音长 2 秒
    t = (0:1/fs:dur-1/fs)';

    % ---- 起音：10ms 平滑升到 1（起音太快会有"咔哒"声）----
    attack = min(t / 0.010, 1);

    % ---- 加法合成：基频 + 2、3 次谐波，每个谐波独立包络 ----
    % 关键：高次谐波衰减更快（2次 0.6s、3次 0.3s），高频"响得快灭得快"，音色才圆润不刺耳
    env1 = attack .* exp(-t / 1.2);           % 基频：慢衰减（钢琴主体）
    env2 = attack .* exp(-t / 0.6);           % 2次谐波：中等衰减
    env3 = attack .* exp(-t / 0.3);           % 3次谐波：快速衰减
    x = 1.0*sin(2*pi*f0*t).*env1 + 0.35*sin(2*pi*2*f0*t).*env2 + 0.12*sin(2*pi*3*f0*t).*env3;

    t_all = [t_all; x];
    if n == 1
        x1 = x; f1 = f0;                      % 存第一个音用于画图
    end
end

% ---- 归一化到 90% 幅度，防削波，转 int16（FPGA 也用 16 位样本）----
t_all = t_all / max(abs(t_all)) * 0.9;
x1    = x1 / max(abs(x1)) * 0.9;

audiowrite('demo_piano.wav', t_all, fs);      % 12 音演示文件
audiowrite('single_C4.wav', x1, fs);          % 单音文件（给队友合奏用）

% ---- 图1：时域波形（前 100ms，看起音和衰减）----
figure('Name', '钢琴单音 C4');
subplot(2,1,1);
t1 = (0:length(x1)-1)/fs;
plot(t1*1000, x1); xlim([0 100]);
xlabel('时间 (ms)'); ylabel('幅度');
title('C4 波形（前100ms：一下很响、慢慢变轻）'); grid on;

% ---- 图2：频谱（主峰应落在基频 f1 附近）----
subplot(2,1,2);
N = 2^nextpow2(length(x1));
X = abs(fft(x1, N));
f = (0:N-1) * fs / N;
plot(f, X); xlim([0 8000]);
xlabel('频率 (Hz)'); ylabel('幅度');
title(sprintf('C4 频谱（主峰应在 %.1f Hz 附近，还有 2、3 倍频小峰）', f1)); grid on;
[~, idx] = max(X);
fprintf('实测峰值频率 = %.1f Hz，理论 = %.1f Hz，误差 = %.2f%%\n', f(idx), f1, abs(f(idx)-f1)/f1*100);

saveas(gcf, 'piano_plots.png');               % 波形+频谱图存成 png
disp('完成！生成：demo_piano.wav / single_C4.wav / piano_plots.png');
disp('正在播放 12 音演示（约 24 秒）……不想听完可按 Ctrl+C');
sound(t_all, fs);                             % 真正播放（声音从这里出来）
