function rom = make_sine_table(n)
% MAKE_SINE_TABLE 生成 n 点 Q15 正弦波表（一个周期）
%   n=1024，输出 int16 范围整数，存 BRAM 供 DDS 查地址
t = (0:n-1)' / n;
rom = round(sin(2*pi*t) * 32767);
end
