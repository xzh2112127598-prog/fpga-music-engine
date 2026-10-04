% export_drum_params.m
% 导出鼓组参数表与 FPGA 查表文件（修正版：24bit 真 FTW）
clear; clc;
addpath('hwlib');
Fs = 48000; PB = 24;

%% 1. 生成参数说明文档（寄存器映射）
fid = fopen('../params/drum_params.md','w');
fprintf(fid,'# 鼓组合成参数表（FPGA 对齐版）\n\n');
fprintf(fid,'## 全局约定\n\n');
fprintf(fid,'- 采样率 48kHz；相位累加器 24bit；波形 ROM：正弦 1024 点、噪声 8192 点\n');
fprintf(fid,'- 频率控制字 FTW = round(f x 2^24 / 48000)\n');
fprintf(fid,'- 音频 Q15；乘法 Q15 x Q15 取高16位；混音 32 路饱和加法树\n\n');
fprintf(fid,'## 寄存器映射\n\n');
fprintf(fid,'| 参数名 | 数值 | 位宽 | FPGA寄存器 | 说明 |\n');
fprintf(fid,'|--------|------|------|-----------|------|\n');
fprintf(fid,'| kick_start_f | 150Hz / FTW %d | 24bit | REG_KICK_F0 | 底鼓起始 |\n', ftw_calc(150,PB,Fs));
fprintf(fid,'| kick_end_f   | 40Hz / FTW %d | 24bit | REG_KICK_F1 | 底鼓结束 |\n', ftw_calc(40,PB,Fs));
fprintf(fid,'| kick_decay_k | 10 (tau~20ms) | 8bit | REG_KICK_DECAY | 衰减移位 |\n');
fprintf(fid,'| snare_body_f | 180Hz / FTW %d | 24bit | REG_SNARE_F | 军鼓主体 |\n', ftw_calc(180,PB,Fs));
fprintf(fid,'| snare_noise_gain | 0.8 | Q15 | REG_SNARE_NOISE | 噪声增益 |\n');
fprintf(fid,'| snare_lp | 5kHz | 16bit | REG_SNARE_LP | 噪声低通 |\n');
fprintf(fid,'| snare_hp | 1kHz | 16bit | REG_SNARE_HP | 噪声高通 |\n');
fprintf(fid,'| hihat_hp | 6kHz | 16bit | REG_HIHAT_HP | 镲高通 |\n');
fprintf(fid,'| hihat_decay_k | 9 (tau~12ms) | 8bit | REG_HIHAT_DECAY | 衰减移位 |\n');
fprintf(fid,'\n## 查表文件\n\n');
fprintf(fid,'- sine_1024.mi：正弦波表（16bit）\n');
fprintf(fid,'- noise_8192.mi：LFSR 噪声波表（16bit）\n');
fprintf(fid,'- kick_sweep_ftw.mi：底鼓 256 点扫频 FTW（24bit）\n');
fprintf(fid,'\n## 合规说明\n\n');
fprintf(fid,'全部声音由振荡器实时合成；波表/FTW 均为合成参数，无预录 PCM。\n');
fclose(fid);
disp('drum_params.md 已更新');

%% 2. 底鼓扫频 256 点真 FTW
t = linspace(0,0.08,256);
freq = 150*(40/150).^(t/0.08);
ftw  = ftw_calc(freq, PB, Fs);
export_mi('../params/kick_sweep_ftw.mi', ftw, 24);
% 兼容旧文件名：同时输出真 FTW 到 kick_sweep.mi
export_mi('../params/kick_sweep.mi', ftw, 24);
disp('kick_sweep_ftw.mi / kick_sweep.mi 已导出（24bit FTW）');

%% 3. 波形 ROM
sine_rom  = make_sine_table(1024);
noise_rom = make_noise_table(8192);
export_mi('../params/sine_1024.mi', sine_rom, 16);
export_mi('../params/noise_8192.mi', noise_rom, 16);
disp('=== 参数导出完成（修正版）===');
