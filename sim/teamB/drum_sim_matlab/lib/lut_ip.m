function v = lut_ip(rom, phase, shift)
% LUT_IP 线性插值查波表（硬件：相邻两点 + 小数部分插值，1个乘法器）
%   phase 相位（整数），shift = 相位位宽 - 地址位宽
addr = floor(phase / 2^shift);
frac = (phase - addr*2^shift) / 2^shift;       % 相位小数 0~1
n = length(rom);
a0 = rom(addr + 1);
a1 = rom(mod(addr + 1, n) + 1);
v = round(a0 + frac*(a1 - a0));
end
