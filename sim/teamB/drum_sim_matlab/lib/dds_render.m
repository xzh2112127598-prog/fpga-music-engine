function [y, phase] = dds_render(rom, n, ftw, phase0, phase_bits)
% DDS_RENDER 定点 DDS 渲染：相位累加器 + 波表查表
%   rom       波形 ROM（Q15），地址位宽 = log2(length(rom))
%   n         输出样本数
%   ftw       频率控制字（24bit）
%   phase0    初始相位（0..2^24-1）
%   phase_bits 相位位宽（24）
naddr = log2(length(rom));
shift = phase_bits - naddr;
phase = phase0;
wrap  = 2^phase_bits;
y = zeros(n,1);
for k = 1:n
    addr  = floor(phase / 2^shift);          % 取相位高 naddr bit（先输出）
    y(k)  = rom(addr + 1);
    phase = phase + ftw;                     % 再累加
    if phase >= wrap, phase = phase - wrap; end
end
end
