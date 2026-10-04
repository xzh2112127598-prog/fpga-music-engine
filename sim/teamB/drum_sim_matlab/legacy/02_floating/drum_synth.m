% drum_synth.m
% 鼓组合成：底鼓/军鼓/镲，采样率48kHz，输出int16
clear; clc; close all;
rng(20251005); % 固定随机种子，保证结果可复现

%% 全局参数
Fs = 48000;
velocity = 127; % 最大力度测试

%% 1. 底鼓 Kick
[y_kick, t_kick] = gen_kick(Fs, velocity);

%% 2. 军鼓 Snare
[y_snare, t_snare] = gen_snare(Fs, velocity);

%% 3. 镲 Hihat
[y_hihat, t_hihat] = gen_hihat(Fs, velocity);

%% 4. 统一导出 int16 音频
audiowrite('../audio/kick.wav', int16(y_kick * 32767), Fs);
audiowrite('../audio/snare.wav', int16(y_snare * 32767), Fs);
audiowrite('../audio/hihat.wav', int16(y_hihat * 32767), Fs);

disp('✅ 音频导出完成，已保存到 ../audio/ 目录');

%% 5. 时域波形图
figure('Name','底鼓时域波形','Position',[100,100,800,300]);
plot(t_kick, y_kick, 'LineWidth',1); grid on;
xlabel('时间 (s)'); ylabel('幅值'); title('Kick 底鼓时域波形');
saveas(gcf, '../fig/kick_time.png');

figure('Name','军鼓时域波形','Position',[100,100,800,300]);
plot(t_snare, y_snare, 'LineWidth',1); grid on;
xlabel('时间 (s)'); ylabel('幅值'); title('Snare 军鼓时域波形');
saveas(gcf, '../fig/snare_time.png');

figure('Name','镲时域波形','Position',[100,100,800,300]);
plot(t_hihat, y_hihat, 'LineWidth',1); grid on;
xlabel('时间 (s)'); ylabel('幅值'); title('Hihat 踩镲时域波形');
saveas(gcf, '../fig/hihat_time.png');

disp('✅ 时域波形图导出完成，已保存到 ../fig/ 目录');

%% 6. 频谱图
figure('Name','底鼓频谱','Position',[100,100,800,300]);
pwelch(y_kick, hann(1024), 512, 1024, Fs);
title('Kick 底鼓功率谱');
saveas(gcf, '../fig/kick_freq.png');

figure('Name','军鼓频谱','Position',[100,100,800,300]);
pwelch(y_snare, hann(1024), 512, 1024, Fs);
title('Snare 军鼓功率谱');
saveas(gcf, '../fig/snare_freq.png');

figure('Name','镲频谱','Position',[100,100,800,300]);
pwelch(y_hihat, hann(1024), 512, 1024, Fs);
title('Hihat 踩镲功率谱');
saveas(gcf, '../fig/hihat_freq.png');

disp('✅ 频谱图导出完成，已保存到 ../fig/ 目录');
disp('=== 第一阶段运行完成 ===');

%% ========== 底鼓生成函数 ==========
function [y, t] = gen_kick(Fs, velocity)
    duration = 0.08;   % 总时长80ms
    t = 0:1/Fs:duration-1/Fs;
    
    % 频率指数扫频：150Hz -> 40Hz
    f_start = 150;
    f_end = 40;
    freq = f_start * (f_end/f_start).^(t/duration);
    phase = 2*pi * cumtrapz(t, freq); % 积分得连续相位
    
    % 指数衰减包络
    env = exp(-t / 0.02);
    
    % 合成 + 力度缩放 + 峰值限制
    y = sin(phase) .* env * (velocity/127) * 0.9;
end

%% ========== 军鼓生成函数 ==========
function [y, t] = gen_snare(Fs, velocity)
    duration = 0.15;  % 总时长150ms
    t = 0:1/Fs:duration-1/Fs;
    
    % 1. 正弦主体（鼓皮振动）
    f_body = 180;
    body = sin(2*pi*f_body*t) * 0.4;
    
    % 2. 带通噪声：白噪声 → 一阶低通 → 一阶高通，等效1k~5kHz带通
    noise = randn(size(t));
    % 一阶低通（截止5kHz）
    lp_alpha = 2*pi*5000 / Fs;
    noise_lp = zeros(size(t));
    for i = 2:length(t)
        noise_lp(i) = noise_lp(i-1) + lp_alpha * (noise(i) - noise_lp(i-1));
    end
    % 一阶高通（截止1kHz）
    hp_alpha = 2*pi*1000 / Fs;
    noise_bp = zeros(size(t));
    prev_in = 0;
    for i = 2:length(t)
        noise_bp(i) = hp_alpha * (noise_bp(i-1) + noise_lp(i) - prev_in);
        prev_in = noise_lp(i);
    end
    noise_bp = noise_bp * 0.6;
    
    % 3. 共同衰减包络
    env = exp(-t / 0.05);
    
    % 合成 + 力度缩放
    y = (body + noise_bp) .* env * (velocity/127) * 0.9;
end

%% ========== 镲生成函数 ==========
function [y, t] = gen_hihat(Fs, velocity)
    duration = 0.04;  % 总时长40ms
    t = 0:1/Fs:duration-1/Fs;
    
    % 一阶高通噪声（截止6kHz，金属敲击感）
    noise = randn(size(t));
    hp_alpha = 2*pi*6000 / Fs;
    noise_hp = zeros(size(t));
    prev_in = 0;
    for i = 2:length(t)
        noise_hp(i) = hp_alpha * (noise_hp(i-1) + noise(i) - prev_in);
        prev_in = noise(i);
    end
    
    % 极短指数衰减
    env = exp(-t / 0.012);
    
    % 合成 + 力度缩放
    y = noise_hp .* env * (velocity/127) * 0.9;
end
