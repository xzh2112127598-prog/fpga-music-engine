function ftw = ftw_calc(f_hz, phase_bits, fs)
% FTW_CALC 由频率计算 DDS 频率控制字
%   FTW = round(f_hz * 2^phase_bits / fs)
%   phase_bits=24, fs=48000 时：440Hz -> 153266, 150Hz -> 52429, 40Hz -> 13981
ftw = round(f_hz * 2^phase_bits / fs);
end
