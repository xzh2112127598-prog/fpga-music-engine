%% gen_lut.m —— 生成三张 LUT 查找表（正弦表 / 频率表 / 包络表）
%  用途：把"波形、音高、音量变化"做成 FPGA 能查的表，输出 .mi 与 .hex 两种格式。
%  用法：MATLAB 里 F5 运行，在当前目录生成 6 个文件。
%  说明：.mi = 高云 EDA ROM 初始化格式（@地址 数据）；.hex = Verilog $readmemh 直接读。
clear; clc;

fs = 48000;   % 采样率，必须和 piano_synth.m / FPGA 一致！

%% 1) 正弦波表：1024 点，16 位有符号（int16）
N = 1024;
sine = round(sin(2*pi*(0:N-1)/N) * 32767);   % 幅度 ±32767（int16 满量程）

fid = fopen('sine_lut.mi', 'w');
for i = 1:N
    fprintf(fid, '@%04X %04X\n', i-1, mod(sine(i), 65536));
end
fclose(fid);

fid = fopen('sine_lut.hex', 'w');
for i = 1:N
    fprintf(fid, '%04X\n', mod(sine(i), 65536));
end
fclose(fid);

%% 2) 频率表：MIDI 0~127 → 32 位频率字（FPGA DDS 相位累加器用）
%    freq_word = round( f * 2^32 / fs )，f = 440 * 2^((midi-69)/12)
fid = fopen('note_freq.mi', 'w');
fid2 = fopen('note_freq.hex', 'w');
for midi = 0:127
    f = 440 * 2^((midi - 69) / 12);
    fw = round(f * 2^32 / fs);               % 32 位无符号频率字
    fprintf(fid,  '@%04X %08X\n', midi, mod(fw, 2^32));
    fprintf(fid2, '%08X\n', mod(fw, 2^32));
end
fclose(fid); fclose(fid2);

%% 3) 包络表：256 点指数衰减曲线（对应 1.2s 时间常数 @48kHz）
%    每点间隔 = 1.2s / 256；衰减因子 exp(-t/1.2)，采样点 n 对应 t = n*1.2/256
env = round(exp(-(0:255) * (1.2/256) / 1.2) * 32767);

fid = fopen('env_lut.mi', 'w');
fid2 = fopen('env_lut.hex', 'w');
for i = 1:256
    fprintf(fid,  '@%04X %04X\n', i-1, mod(env(i), 65536));
    fprintf(fid2, '%04X\n', mod(env(i), 65536));
end
fclose(fid); fclose(fid2);

%% 完成提示
fprintf('已生成 6 个文件：\n');
fprintf('  sine_lut.mi/.hex   %d 行（1024 点正弦表）\n', N);
fprintf('  note_freq.mi/.hex  %d 行（MIDI 0-127 频率表）\n', 128);
fprintf('  env_lut.mi/.hex    %d 行（256 点包络表）\n', 256);
disp('用记事本打开 .mi 检查：每行"@地址 数据"十六进制，无 0x 前缀（对照规划文档 3.5.2）。');
