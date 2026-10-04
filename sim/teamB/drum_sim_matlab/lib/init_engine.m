function [P, sine_rom, noise_rom] = init_engine(out_dir)
% INIT_ENGINE  构建全局定点参数 P 与两张波形 ROM
% ============================================================
% 全工程【唯一参数源】。改参数只改这里，主脚本与导出脚本自动同步，
% 杜绝 params/*.md 与 RTL 口径漂移（24bit/32bit 事故的根因）。
%
% 队长口径（2026-10-04）：
%   采样率 48000；样本 int16（Q15）
%   频率字 freq_word = round(f * 2^32 / 48000)   <-- 32bit，不是 24bit
%   钢琴每 voice 3 谐波，幅度比 1 : 0.35 : 0.12
%   包络时间常数 基频1.2s / 2次0.6s / 3次0.3s，起音 10ms
%
% 用法：
%   addpath('lib');
%   [P, sine_rom, noise_rom] = init_engine();        % 只建参数
%   [P, sine_rom, noise_rom] = init_engine('params');% 同时导出 .mi / note_freq.md
% ============================================================
if nargin < 1, out_dir = ''; end

Fs = 48000;
PB = 32;                                  % 相位 / 频率字位宽

sine_rom  = make_sine_table(1024);        % 1024 x int16
noise_rom = make_noise_table(8192);       % 8192 x int16 (LFSR)

P = struct();
P.fs = Fs;
P.pb = PB;

% ---- 波表地址移位（相位高位取地址）----
P.sine_shift  = PB - 10;                  % 22：1024 点表取相位高 10bit
P.noise_shift = PB - 13;                  % 19：8192 点表取相位高 13bit
P.noise_ftw   = 2^(PB - 13);              % 524288：噪声每样本地址 +1

% ---- 底鼓扫频 150 -> 55Hz，80ms，指数滑音 ----
%     （口径说明：10.5 任务书写 150->40Hz，本工程实测 55Hz 冲击感更好，
%       已与队长确认保持 55Hz；如要改只需改下面 P.kick_f1）
P.kick_f0   = 150;
P.kick_f1   = 55;
P.kick_time = 0.08;
P.kick_n    = round(P.kick_time * Fs);    % 3840 样本
tt256 = linspace(0, P.kick_time, 256);
fq = P.kick_f0 * (P.kick_f1 / P.kick_f0).^(tt256 / P.kick_time);
P.kick_sweep = ftw_calc(fq, PB, Fs);      % 256 x 32bit FTW
P.click_n   = round(0.01 * Fs);           % 鼓槌击皮 click 持续 10ms

% ---- 军鼓 / 镲 的固定频率（32bit FTW 由 ftw_calc 现场算，见 voice_render）----
P.snare_f   = [180 200];                  % 鼓膜双模态
P.hihat_res = [6200 7900 9400];           % 镲片金属非谐共振

% ---- 定点一阶滤波器系数（低通 1-exp(-wc)，高通 exp(-wc)）----
P.lp3k  = 1 - exp(-2*pi*3000/Fs);         % kick click 低通
P.lp9k  = 1 - exp(-2*pi*9000/Fs);         % snare 噪声低通
P.hp5k  =     exp(-2*pi*5000/Fs);         % snare 噪声高通 -> 通带 5~9kHz
P.lp10k = 1 - exp(-2*pi*10000/Fs);        % hihat 噪声低通
P.hp7k  =     exp(-2*pi*7000/Fs);         % hihat 噪声高通 -> 通带 7~10kHz

% ---- 弯音表（41 点：-2..+2 半音，Q15 比例）----
semi = (-2:0.1:2)';
P.bend_tbl = round(2.^(semi/12) * 32768);

% ---- LFO：5Hz 颤音（仅钢琴）----
P.lfo_ftw   = ftw_calc(5, PB, Fs);
P.lfo_depth = [0 0 0 960];

% ---- 鼓 ADSR（attack_step, decay_k, sustain, release_k）----
a1 = struct('attack_step',341,'decay_k',11,'sustain',0,'release_k',11);  % kick
a2 = struct('attack_step',341,'decay_k',11,'sustain',0,'release_k',11);  % snare
a3 = struct('attack_step',683,'decay_k', 9,'sustain',0,'release_k', 9);  % hihat
a4 = struct('attack_step',137,'decay_k',16,'sustain',2000,'release_k',14);
P.adsr = [a1 a2 a3 a4];

% ---- 钢琴 3 独立包络（队长口径）----
P.piano_attack = round(32767 / (0.01 * Fs));   % 起音 10ms -> 每样本步进
P.piano_khold  = [16 15 14];                   % 按住衰减 tau 1.2 / 0.6 / 0.3 s
P.piano_krel   = 11;                           % 松键衰减
P.piano_ratio  = [1 0.35 0.12];                % 3 谐波幅度比

if ~isempty(out_dir)
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    export_mi(fullfile(out_dir, 'sine_1024.mi'),  sine_rom,  16);
    export_mi(fullfile(out_dir, 'noise_8192.mi'), noise_rom, 16);
    export_mi(fullfile(out_dir, 'kick_sweep.mi'), P.kick_sweep, 32);
    write_note_freq(fullfile(out_dir, 'note_freq.md'), PB, Fs);
end
end

function write_note_freq(fname, PB, Fs)
% WRITE_NOTE_FREQ 导出 MIDI 0-127 频率与 32bit 频率字（供队员 A / RTL 共用）
fid = fopen(fname, 'w');
fprintf(fid, '# MIDI 0-127 频率与 32bit 频率字（Fs=48000）\n\n');
fprintf(fid, 'freq_word = round(f x 2^%d / 48000)\n\n', PB);
fprintf(fid, '| MIDI | 音名 | 频率Hz | 频率字 |\n|---|---|---|---|\n');
for m = 0:127
    f = 440 * 2^((m - 69) / 12);
    fprintf(fid, '| %d | %s | %.2f | %d |\n', m, midi_name(m), f, ftw_calc(f, PB, Fs));
end
fclose(fid);
end
