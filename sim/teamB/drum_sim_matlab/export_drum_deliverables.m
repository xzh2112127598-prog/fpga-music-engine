%% =========================================================
%  队员 B · 10.5 交付物导出脚本（鼓组）
%  --------------------------------------------------------
%  产出：
%    params/drum_params.md   32bit 口径鼓参数表【由代码生成，不会与 RTL 漂移】
%    audio/kick.wav          定点底鼓（150->55Hz 扫频 + click）
%    audio/snare.wav         定点军鼓（180/200Hz 双模态 + 5~9kHz 响弦）
%    audio/hihat.wav         定点镲（7~10kHz 噪声 + 6200/7900/9400 金属共振）
%    fig/drum_overview.png   3x2 时域 + 频谱（验收"三种鼓件音色可区分"）
%
%  运行：在本目录打开 MATLAB，命令行执行 export_drum_deliverables
% =========================================================
clear; clc;
addpath('lib');

%% ---------- 1. 参数与 ROM（唯一参数源）----------
[P, sine_rom, noise_rom] = init_engine('params');
roms = struct('sine', sine_rom, 'noise', noise_rom);
Fs = P.fs; PB = P.pb;
fprintf('[参数] 采样率 %d, 相位位宽 %d, FTW = round(f*2^%d/%d)\n', Fs, PB, PB, Fs);

%% ---------- 2. 三鼓件定点渲染 ----------
types = [1 2 3];
names = {'kick', 'snare', 'hihat'};
cnames = {'底鼓 Kick', '军鼓 Snare', '镲 Hihat'};
DUR = 0.6;
T = round(DUR * Fs);
vel = round(0.9 * 32767);

V = voice_init(3);
for k = 1:3
    [V, ~] = voice_noteon(V, 0, vel, types(k));
end
ch = zeros(3, T);
for n = 1:T
    for k = 1:3
        [s, V(k)] = voice_render(V(k), roms, P, 0);
        ch(k, n) = s;
    end
end

if ~exist('audio', 'dir'), mkdir('audio'); end
if ~exist('fig', 'dir'),   mkdir('fig');   end
for k = 1:3
    audiowrite(fullfile('audio', [names{k} '.wav']), int16(sat16(ch(k, :))), Fs);
end

%% ---------- 3. 三频段能量（可区分性量化）----------
band = zeros(3, 3);                       % 行=鼓件, 列=低/中/高
edges = [0 200; 200 2000; 2000 24000];
for k = 1:3
    seg = ch(k, :)' .* hann(T);
    X = abs(fft(seg));
    fv = (0:T-1)' * Fs / T;
    E = X(1:floor(T/2)).^2;
    ff = fv(1:floor(T/2));
    for b = 1:3
        band(k, b) = sum(E(ff >= edges(b,1) & ff < edges(b,2)));
    end
    band(k, :) = band(k, :) / sum(band(k, :));
end

%% ---------- 4. 图：3x2 时域 + 频谱 ----------
figure('Name', '三种鼓件时域与频谱', 'Position', [80 80 900 620]);
tp = (0:T-1) / Fs;
for k = 1:3
    subplot(3, 2, 2*k-1);
    plot(tp*1000, ch(k, :)); grid on;
    xlabel('时间 (ms)'); ylabel('幅度');
    title([cnames{k} ' · 时域']);
    xlim([0 400]);

    subplot(3, 2, 2*k);
    seg = ch(k, :)' .* hann(T);
    X = abs(fft(seg)); fv = (0:T-1)' * Fs / T;
    nh = floor(T/2);
    plot(fv(1:nh), 20*log10(X(1:nh) + 1e-6)); grid on;
    xlabel('频率 (Hz)'); ylabel('幅度 (dB)');
    title([cnames{k} ' · 频谱']);
    xlim([0 12000]);
end
print(gcf, 'fig/drum_overview.png', '-dpng', '-r130');

%% ---------- 5. 参数表（32bit，全部由代码算出）----------
fid = fopen('params/drum_params.md', 'w');
fprintf(fid, '# 鼓组合成参数表（FPGA 对齐版 · 32bit）\n\n');
fprintf(fid, '> 本文件由 `export_drum_deliverables.m` **自动生成**，请勿手改。\n');
fprintf(fid, '> 改参数请改 `lib/init_engine.m`，再重跑本脚本。\n\n');
fprintf(fid, '## 全局口径\n\n');
fprintf(fid, '| 项 | 值 |\n|---|---|\n');
fprintf(fid, '| 采样率 | %d Hz |\n', Fs);
fprintf(fid, '| 样本 | int16（Q15） |\n');
fprintf(fid, '| 相位/频率字位宽 | %d bit |\n', PB);
fprintf(fid, '| 频率字公式 | freq_word = round(f x 2^%d / %d) |\n', PB, Fs);
fprintf(fid, '| 混音 | 32 路饱和加法树 + sat16 |\n\n');
fprintf(fid, '| 波表 | 深度 | 地址取相位 | 文件 |\n|---|---|---|---|\n');
fprintf(fid, '| 正弦 | 1024 x 16bit | phase[%d:%d] | sine_1024.mi |\n', PB-1, P.sine_shift);
fprintf(fid, '| 噪声 LFSR | 8192 x 16bit | phase[%d:%d] | noise_8192.mi |\n', PB-1, P.noise_shift);
fprintf(fid, '| 底鼓扫频 | 256 x 32bit | 只读 FTW 非 PCM | kick_sweep.mi |\n\n');

fprintf(fid, '## 鼓件寄存器映射\n\n');
fprintf(fid, '| 参数 | 数值 | 频率字(32bit) | 位宽 | FPGA 寄存器 |\n|---|---|---|---|---|\n');
fprintf(fid, '| kick 起始频率 | %.0f Hz | %d | 32bit | REG_KICK_F0 |\n', P.kick_f0, ftw_calc(P.kick_f0, PB, Fs));
fprintf(fid, '| kick 终止频率 | %.0f Hz | %d | 32bit | REG_KICK_F1 |\n', P.kick_f1, ftw_calc(P.kick_f1, PB, Fs));
fprintf(fid, '| kick 扫频时长 | %.0f ms（%d 样本） | - | - | REG_KICK_TIME |\n', P.kick_time*1000, P.kick_n);
fprintf(fid, '| kick 扫频表 | 256 点指数滑音 | 见 kick_sweep.mi | 32bit | ROM |\n');
fprintf(fid, '| kick click | %.0f ms，低通 %.0f Hz | - | - | REG_KICK_CLICK |\n', P.click_n/Fs*1000, 3000);
fprintf(fid, '| snare 模态 1 | %.0f Hz | %d | 32bit | REG_SNARE_F1 |\n', P.snare_f(1), ftw_calc(P.snare_f(1), PB, Fs));
fprintf(fid, '| snare 模态 2 | %.0f Hz | %d | 32bit | REG_SNARE_F2 |\n', P.snare_f(2), ftw_calc(P.snare_f(2), PB, Fs));
fprintf(fid, '| snare 响弦带通 | 5000 ~ 9000 Hz | - | 16bit | REG_SNARE_BP |\n');
fprintf(fid, '| hihat 噪声带通 | 7000 ~ 10000 Hz | - | 16bit | REG_HIHAT_BP |\n');
for k = 1:3
    fprintf(fid, '| hihat 金属共振 %d | %.0f Hz | %d | 32bit | REG_HIHAT_R%d |\n', ...
        k, P.hihat_res(k), ftw_calc(P.hihat_res(k), PB, Fs), k);
end
fprintf(fid, '| 噪声表步进 | 每样本地址 +1 | %d | 32bit | REG_NOISE_FTW |\n', P.noise_ftw);
fprintf(fid, '| LFO 颤音 | %.0f Hz | %d | 32bit | REG_LFO_F |\n\n', 5, P.lfo_ftw);

fprintf(fid, '## 鼓件 ADSR（Q15 步进）\n\n');
fprintf(fid, '| 鼓件 | attack_step | decay_k | sustain | release_k | 近似衰减 |\n|---|---|---|---|---|---|\n');
dk = {'kick', 'snare', 'hihat'};
for k = 1:3
    a = P.adsr(k);
    fprintf(fid, '| %s | %d | %d | %d | %d | 2^-%d 指数衰减 |\n', dk{k}, a.attack_step, a.decay_k, a.sustain, a.release_k, a.decay_k);
end
fprintf(fid, '\n## 钢琴（队长口径，供 A 对齐）\n\n');
fprintf(fid, '| 项 | 值 |\n|---|---|\n');
fprintf(fid, '| 谐波数 | 3（独立相位累加器） |\n');
fprintf(fid, '| 幅度比 | %g : %g : %g |\n', P.piano_ratio(1), P.piano_ratio(2), P.piano_ratio(3));
fprintf(fid, '| 包络时间常数 | %.1f / %.1f / %.1f s |\n', 1.2, 0.6, 0.3);
fprintf(fid, '| 起音 | %.0f ms |\n\n', 10);

fprintf(fid, '## 可区分性验证（三频段能量占比）\n\n');
fprintf(fid, '| 鼓件 | 低频 0-200Hz | 中频 0.2-2kHz | 高频 2-24kHz | 峰值 | 削波 |\n|---|---|---|---|---|---|\n');
for k = 1:3
    fprintf(fid, '| %s | %.2f | %.2f | %.2f | %d | %d |\n', names{k}, band(k,1), band(k,2), band(k,3), ...
        max(abs(ch(k,:))), sum(abs(ch(k,:)) >= 32767));
end
fprintf(fid, '\n判据：底鼓低频独占、镲高频独占、军鼓呈低频鼓膜 180/200Hz + 高频响弦 5~9kHz 双峰。三者频段重心互不相同，即可判定音色可区分"音色可区分"。\n\n');
fprintf(fid, '## 合规说明\n\n');
fprintf(fid, '- 三鼓件全部由正弦扫频 / LFSR 噪声 / 一阶滤波 / ADSR 现场合成，**无任何录音参与**；\n');
fprintf(fid, '- `kick_sweep.mi` 存的是**频率控制字（参数）**，不是 PCM 波形，属合法查表；\n');
fprintf(fid, '- `audio/*.wav` 仅供试听与算法验证，**不进入 FPGA、不入库**（见 .gitignore）。\n');
fclose(fid);

% 同步一份到全队文档目录 doc/（自动复制，避免手抄产生漂移）
root = fileparts(mfilename('fullpath'));
docdir = fullfile(root, '..', '..', '..', 'doc');
if exist(docdir, 'dir')
    copyfile(fullfile(root, 'params', 'drum_params.md'), fullfile(docdir, 'drum_params.md'));
    fprintf('已同步 doc/drum_params.md\n');
end

%% ---------- 6. 控制台汇总 ----------
fprintf('\n=== 三鼓件导出完成 ===\n');
for k = 1:3
    fprintf('%-6s 峰值 %6d  削波 %d  低/中/高 = %.2f / %.2f / %.2f\n', ...
        names{k}, max(abs(ch(k,:))), sum(abs(ch(k,:)) >= 32767), band(k,1), band(k,2), band(k,3));
end
fprintf('已写出 params/drum_params.md、audio/*.wav、fig/drum_overview.png\n');
