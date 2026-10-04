function tbl = vel_curve(gamma)
% VEL_CURVE 力度非线性映射表（128 点 ROM）：原始力度 -> 输出力度
%   gamma<1 提升弱击响度（符合人耳感知），gamma=1 为线性
if nargin < 1, gamma = 0.8; end
raw = 0:127;
tbl = round(127 * (raw/127).^gamma);
tbl = min(127, tbl);
end
