function y = mix_tree(channels)
% MIX_TREE 定点饱和加法树：n 路 Q15 逐级两两相加 -> 限幅 Q15
%   channels: n x T（Q15 整数）
lv = channels;
while size(lv,1) > 1
    if mod(size(lv,1),2) == 1, lv(end+1,:) = 0; end
    lv = lv(1:2:end,:) + lv(2:2:end,:);
end
y = sat16(lv);
end
