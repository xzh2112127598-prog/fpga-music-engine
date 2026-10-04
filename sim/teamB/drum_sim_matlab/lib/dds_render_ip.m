function [y, phase] = dds_render_ip(rom, n, ftw, phase0, phase_bits)
% DDS_RENDER_IP 带线性插值的定点 DDS（乐音高保真版）
naddr = log2(length(rom));
shift = phase_bits - naddr;
phase = phase0;
wrap  = 2^phase_bits;
y = zeros(n,1);
for k = 1:n
    y(k)  = lut_ip(rom, phase, shift);
    phase = phase + ftw;
    if phase >= wrap, phase = phase - wrap; end
end
end
