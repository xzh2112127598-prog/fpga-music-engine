function st = reverb_init()
% REVERB_INIT Schroeder/Freeverb 混响状态（4 并行 comb + 2 串联 allpass）
%   延迟长度按48kHz缩放；硬件：延迟线放 BRAM，每滤波器1个读写指针
% comb（48k）
clen = [1694 1759 1622 1547];
% allpass（48k）
alen = [571 604];
st.clen = clen; st.alen = alen;
st.cbuf = zeros(4, max(clen));     % comb 延迟缓冲
st.abuf = zeros(2, max(alen));     % allpass 延迟缓冲
st.cidx = ones(1,4);               % comb 写指针
st.aidx = ones(1,2);               % allpass 写指针
st.cfdbk = round(0.84*32768);      % comb 反馈 Q15
st.ag    = round(0.5*32768);       % allpass 系数 Q15
end
