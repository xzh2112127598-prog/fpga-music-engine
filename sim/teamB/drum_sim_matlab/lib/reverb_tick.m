function [y, st] = reverb_tick(x, st)
% REVERB_TICK 混响逐样本处理（硬件：4 comb 并行 -> 2 allpass 串联）
% 4 个 comb 并行
csum = 0;
for c = 1:4
    idx = st.cidx(c);
    d = st.cbuf(c, idx);                       % 读延迟
    out = x + q15mul(d, st.cfdbk);
    st.cbuf(c, idx) = out;                    % 写回
    idx = idx + 1;
    if idx > st.clen(c), idx = 1; end
    st.cidx(c) = idx;
    csum = csum + out;
end
comb_out = floor(csum/4);                     % 4 路平均
% 2 个 allpass 串联
ap = comb_out;
for a = 1:2
    idx = st.aidx(a);
    bo = st.abuf(a, idx);
    y_a = bo - q15mul(ap, st.ag);             % allpass 输出
    st.abuf(a, idx) = ap + q15mul(y_a, st.ag);
    idx = idx + 1;
    if idx > st.alen(a), idx = 1; end
    st.aidx(a) = idx;
    ap = y_a;
end
y = ap;
end
