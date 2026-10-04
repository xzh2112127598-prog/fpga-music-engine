function rom = make_noise_table(n, seed)
% MAKE_NOISE_TABLE 用 23bit Galois LFSR 生成 n 点 Q15 白噪声波表
%   多项式 x^23 + x^18 + 1；每输出 16bit 推进 16 个 LFSR 时钟
%   该波表是噪声振荡器的“波形 ROM”（与正弦表地位相同），不是预录音频
if nargin < 2, seed = 20251005; end
reg = seed;
rom = zeros(n,1);
mask = 2^22 + 2^17;     % Galois 反馈掩码（bit22, bit17）
for i = 1:n
    w = 0;
    for b = 1:16
        lsb = bitand(reg,1);
        reg = bitshift(reg,-1);
        if lsb, reg = bitxor(reg, mask); end
        w = w + lsb * 2^(16-b);
    end
    if w >= 32768, w = w - 65536; end   % 转有符号
    rom(i) = w;
end
end
