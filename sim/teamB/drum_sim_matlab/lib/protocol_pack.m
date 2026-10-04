function frames = protocol_pack(events)
% PROTOCOL_PACK  演奏事件 -> 协议 v1 的 12 字节定长帧
% ============================================================
% 帧格式（小端），与 doc/protocol_v1.md 一致：
%   [0]=AA [1]=55
%   [2]=bit7:6 乐器ID(00钢琴/01鼓/10笛/11吉他) bit4 事件(0触发/1松开) bit3:0 通道
%   [3]=保留
%   [4:5]=时间戳 uint16 单位5ms
%   [6:7]=音符 int16（钢琴=MIDI音高；鼓=鼓件编码 0底鼓/1军鼓/2闭镲/3开镲/4桶鼓）
%   [8:9]=力度 uint16
%   [10]=音长 uint8 单位0.05s（0=按住直到松开）
%   [11]=前11字节异或校验
%
% 输入 events：N x 5 矩阵 [time_s, inst, code, vel, dur_s]
%   inst : 0=钢琴 1=鼓 2=笛 3=吉他
%   code : 钢琴=MIDI 音高（60=中央C）；鼓=0底鼓/1军鼓/2闭镲/3开镲/4桶鼓
%   vel  : 0..127（内部按 <<9 映射成 uint16，与队长的 32768=vel64 一致）
%   dur_s: 秒；0 表示按住直到松开
% 输出 frames：N x 12 uint8
% ============================================================
    if isempty(events), frames = zeros(0,12,'uint8'); return; end

    N = size(events,1);
    frames = zeros(N,12,'uint8');
    for i = 1:N
        t_s  = events(i,1);
        inst = events(i,2);
        code = events(i,3);
        vel  = events(i,4);
        dur  = events(i,5);

        ts   = round(t_s / 0.005);                 % 时间戳单位 5ms
        ts   = min(max(ts,0), 65535);
        v16  = min(max(round(vel),0),127) * 512;   % 7bit -> uint16（队长用 64->32768）
        d8   = min(max(round(dur / 0.05),0), 255); % 音长单位 0.05s

        f = zeros(1,12,'uint8');
        f(1) = 170;                                % 0xAA
        f(2) = 85;                                 % 0x55
        f(3) = bitor(bitshift(bitand(inst,3),6), bitand(0,15));  % 事件=0（触发），通道=0
        f(4) = 0;
        f(5) = bitand(ts, 255);                    % 小端
        f(6) = bitand(bitshift(ts,-8), 255);
        nc   = mod(round(code), 65536);            % int16 补码
        f(7) = bitand(nc, 255);
        f(8) = bitand(bitshift(nc,-8), 255);
        f(9)  = bitand(v16, 255);
        f(10) = bitand(bitshift(v16,-8), 255);
        f(11) = d8;
        chk = 0;
        for k = 1:11, chk = bitxor(chk, double(f(k))); end
        f(12) = chk;
        frames(i,:) = f;
    end
end
