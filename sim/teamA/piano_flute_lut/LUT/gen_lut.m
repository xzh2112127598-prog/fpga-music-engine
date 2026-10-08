%% gen_lut.m —— 生成 FPGA 全部查找表（v2：支持 36 键钢琴谐波规格）
%  用途：把"波形、音高、泛音结构、音量变化"做成 FPGA 能查的表。
%  版本：v2（2026-10-05）—— 新增泛音频率/幅度/衰减速率表，与 piano_36keys_C3_B5.m 的
%        非谐和性加性合成模型（B=0.0003、幅度 1/k^1.8、衰减 1/k^0.7）对齐，供 FPGA 用前 4 个泛音实现。
%  用法：MATLAB 里 F5 运行，在当前目录生成 12 个文件（.mi 与 .hex 各 6 组）。
%  说明：.mi = 高云 EDA ROM 初始化格式（@地址 数据）；.hex = Verilog $readmemh 直接读。
clear; clc;

fs = 48000;      % 采样率：必须与整机 48kHz 规格一致！
B  = 0.0003;     % 弦非谐和系数（与 piano_36keys_C3_B5.m 完全一致）
NH = 4;          % FPGA 泛音数：8 voice × 4 = 32 + 鼓 8 = 40 振荡器（≥32 达标）

%% 1) 正弦波表：1024 点，16 位有符号（int16）—— 所有泛音共用这一张
N = 1024;
sine = round(sin(2*pi*(0:N-1)/N) * 32767);

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

%% 2) 基频频率表：MIDI 0~127 → 32 位频率字（FPGA DDS 相位累加器用）
%    freq_word = round( f * 2^32 / fs )，f = 440 * 2^((midi-69)/12)
fid = fopen('note_freq.mi', 'w');
fid2 = fopen('note_freq.hex', 'w');
for midi = 0:127
    f = 440 * 2^((midi - 69) / 12);
    fw = round(f * 2^32 / fs);
    fprintf(fid,  '@%04X %08X\n', midi, mod(fw, 2^32));
    fprintf(fid2, '%08X\n', mod(fw, 2^32));
end
fclose(fid); fclose(fid2);

%% 3) 泛音频率字表：地址 = midi*NH + (k-1)，共 128*4=512 行（32 位）
%    含非谐和系数：f_k = k*f0*sqrt(1+B*k^2)
fid = fopen('harm_freq.mi', 'w');
fid2 = fopen('harm_freq.hex', 'w');
for midi = 0:127
    f0 = 440 * 2^((midi - 69) / 12);
    for k = 1:NH
        fk  = k * f0 * sqrt(1 + B*k^2);
        fwk = round(fk * 2^32 / fs);
        addr = midi*NH + (k-1);
        fprintf(fid,  '@%04X %08X\n', addr, mod(fwk, 2^32));
        fprintf(fid2, '%08X\n', mod(fwk, 2^32));
    end
end
fclose(fid); fclose(fid2);

%% 4) 泛音幅度表：amp_k = 1/k^1.8，归一化到基频=32767（16 位）
amp = round((1:NH).^-1.8 * 32767);
fid = fopen('harm_amp.mi', 'w');
fid2 = fopen('harm_amp.hex', 'w');
for k = 1:NH
    fprintf(fid,  '@%04X %04X\n', k-1, mod(amp(k), 65536));
    fprintf(fid2, '%04X\n', mod(amp(k), 65536));
end
fclose(fid); fclose(fid2);

%% 5) 泛音衰减速率表：rate_k = 1/k^0.7（×32768 定点），越大衰减越快
%    FPGA 用法：包络计数器步进 = 基准步进 × rate_k / 32768
rate = round((1:NH).^-0.7 * 32768);
fid = fopen('harm_rate.mi', 'w');
fid2 = fopen('harm_rate.hex', 'w');
for k = 1:NH
    fprintf(fid,  '@%04X %04X\n', k-1, mod(rate(k), 65536));
    fprintf(fid2, '%04X\n', mod(rate(k), 65536));
end
fclose(fid); fclose(fid2);

%% 6) 基准包络表：256 点指数衰减（基频 tau=1.2s，256 点覆盖 2.5s）
%    env(n) = exp(-n*dt/tau)，dt = 2.5/256
dt  = 2.5 / 256;
env = round(exp(-(0:255) * dt / 1.2) * 32767);

fid = fopen('env_lut.mi', 'w');
fid2 = fopen('env_lut.hex', 'w');
for i = 1:256
    fprintf(fid,  '@%04X %04X\n', i-1, mod(env(i), 65536));
    fprintf(fid2, '%04X\n', mod(env(i), 65536));
end
fclose(fid); fclose(fid2);

%% 完成提示
fprintf('已生成 12 个文件（v2）：\n');
fprintf('  sine_lut.mi/.hex     %d 行  1024 点正弦表（16 位）\n', N);
fprintf('  note_freq.mi/.hex    %d 行  MIDI 0-127 基频频率字（32 位）\n', 128);
fprintf('  harm_freq.mi/.hex    %d 行  泛音频率字，地址=midi*4+(k-1)，含非谐和系数 B=%.4f\n', 128*NH, B);
fprintf('  harm_amp.mi/.hex     %d 行  泛音幅度 1/k^1.8 = %s\n', NH, mat2str(amp'));
fprintf('  harm_rate.mi/.hex    %d 行  泛音衰减速率 1/k^0.7 = %s\n', NH, mat2str(rate'));
fprintf('  env_lut.mi/.hex      %d 行  基准包络表（tau=1.2s）\n', 256);
disp('FPGA 查表约定：地址=音符MIDI*4+(泛音序号-1)；包络按 harm_rate 加速/减速读取。');
disp('用记事本打开 .mi 检查：每行"@地址 数据"十六进制，无 0x 前缀。');
