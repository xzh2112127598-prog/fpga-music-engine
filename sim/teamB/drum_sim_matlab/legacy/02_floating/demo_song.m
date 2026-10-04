% demo_song.m
% 钢琴+鼓合奏演示，48kHz，int16输出
clear; clc; close all;
rng(20251005);

Fs = 48000;
bpm = 120;
beat = 60/bpm; % 一拍0.5秒

%% 1. 生成钢琴旋律（C大调音阶，八分音符）
notes = [60 62 64 65 67 69 71 72]; % C4~C5
note_dur = beat * 0.5;
total_len = round(length(notes) * note_dur * Fs);
y_piano = zeros(1, total_len);

for i = 1:length(notes)
    idx_start = round((i-1)*note_dur*Fs) + 1;
    idx_end = idx_start + round(note_dur*Fs) - 1;
    if idx_end > total_len
        idx_end = total_len;
    end
    y_note = gen_piano_simple(Fs, notes(i), 100, note_dur);
    len_note = min(length(y_note), idx_end-idx_start+1);
    y_piano(idx_start:idx_start+len_note-1) = y_piano(idx_start:idx_start+len_note-1) + y_note(1:len_note);
end

%% 2. 生成鼓点（8拍：底鼓1/3/5/7，军鼓2/4/6/8，镲每拍都有）
beats = 8;
total_drum_len = round(beats * beat * Fs);
y_drum = zeros(1, total_drum_len);

kick_len = round(0.08 * Fs);
snare_len = round(0.15 * Fs);
hihat_len = round(0.04 * Fs);

for i = 1:beats
    idx = round((i-1)*beat*Fs) + 1;
    
    % 底鼓：奇数拍
    if mod(i, 2) == 1
        y_kick = gen_kick(Fs, 127);
        len = min(kick_len, total_drum_len - idx + 1);
        y_drum(idx:idx+len-1) = y_drum(idx:idx+len-1) + y_kick(1:len);
    end
    
    % 军鼓：偶数拍
    if mod(i, 2) == 0
        y_snare = gen_snare(Fs, 110);
        len = min(snare_len, total_drum_len - idx + 1);
        y_drum(idx:idx+len-1) = y_drum(idx:idx+len-1) + y_snare(1:len);
    end
    
    % 镲：每拍
    y_hihat = gen_hihat(Fs, 80);
    len = min(hihat_len, total_drum_len - idx + 1);
    y_drum(idx:idx+len-1) = y_drum(idx:idx+len-1) + y_hihat(1:len);
end

%% 3. 混音 + 防削波
len = min(length(y_piano), length(y_drum));
y_mix = y_piano(1:len) * 0.6 + y_drum(1:len) * 0.4;

peak = max(abs(y_mix));
if peak > 0.95
    y_mix = y_mix * 0.95 / peak;
    disp(['自动增益调整：', num2str(0.95/peak)]);
end

%% 4. 导出音频 + 波形图
t = 0:1/Fs:(len-1)/Fs;
audiowrite('../audio/demo_mix.wav', int16(y_mix * 32767), Fs);

figure('Name','合奏时域波形','Position',[100,100,900,300]);
plot(t, y_mix, 'LineWidth', 0.8); grid on;
xlabel('时间 (s)'); ylabel('幅值'); title('钢琴+鼓 合奏时域波形');
saveas(gcf, '../fig/demo_mix_time.png');

disp('✅ 合奏Demo生成完成');
disp(['总时长：', num2str(len/Fs), 's']);
disp(['峰值：', num2str(peak)]);

%% ========== 简化钢琴函数 ==========
function y = gen_piano_simple(Fs, note, velocity, duration)
    f = 440 * 2^((note-69)/12);
    t = 0:1/Fs:duration-1/Fs;
    
    % 基频+2次+3次谐波
    y1 = sin(2*pi*f*t);
    y2 = 0.4 * sin(2*pi*2*f*t);
    y3 = 0.15 * sin(2*pi*3*f*t);
    
    % 5ms起音 + 指数衰减包络
    env_attack = min(1, t/0.005);
    env_decay = exp(-t / 1.2);
    env = env_attack .* env_decay;
    
    y = (y1 + y2 + y3) .* env * (velocity/127) * 0.3;
end

%% ========== 复用三个鼓函数 ==========
function [y, t] = gen_kick(Fs, velocity)
    duration = 0.08;
    t = 0:1/Fs:duration-1/Fs;
    f_start = 150; f_end = 40;
    freq = f_start * (f_end/f_start).^(t/duration);
    phase = 2*pi * cumtrapz(t, freq);
    env = exp(-t / 0.02);
    y = sin(phase) .* env * (velocity/127) * 0.9;
end

function [y, t] = gen_snare(Fs, velocity)
    duration = 0.15;
    t = 0:1/Fs:duration-1/Fs;
    f_body = 180;
    body = sin(2*pi*f_body*t) * 0.4;
    
    noise = randn(size(t));
    lp_alpha = 2*pi*5000 / Fs;
    noise_lp = zeros(size(t));
    for i = 2:length(t)
        noise_lp(i) = noise_lp(i-1) + lp_alpha * (noise(i) - noise_lp(i-1));
    end
    hp_alpha = 2*pi*1000 / Fs;
    noise_bp = zeros(size(t));
    prev_in = 0;
    for i = 2:length(t)
        noise_bp(i) = hp_alpha * (noise_bp(i-1) + noise_lp(i) - prev_in);
        prev_in = noise_lp(i);
    end
    noise_bp = noise_bp * 0.6;
    
    env = exp(-t / 0.05);
    y = (body + noise_bp) .* env * (velocity/127) * 0.9;
end

function [y, t] = gen_hihat(Fs, velocity)
    duration = 0.04;
    t = 0:1/Fs:duration-1/Fs;
    noise = randn(size(t));
    hp_alpha = 2*pi*6000 / Fs;
    noise_hp = zeros(size(t));
    prev_in = 0;
    for i = 2:length(t)
        noise_hp(i) = hp_alpha * (noise_hp(i-1) + noise(i) - prev_in);
        prev_in = noise(i);
    end
    env = exp(-t / 0.012);
    y = noise_hp .* env * (velocity/127) * 0.9;
end
