function ev = protocol_unpack(frames)
% PROTOCOL_UNPACK  协议 v1 的 12 字节帧 -> 演奏事件
%   输入 frames：N x 12 uint8（或.bin 文件按 12 字节切分）
%   输出 ev：结构体数组，字段 time_s / inst / event / chan / code / vel / dur_s / ok
%            ok = 校验通过与否
%
%   ⚠️ 鼓件编码与 B 的 voice 类型【不同】，必须用 DRUM2VOICE 映射：
%        协议 0底鼓 1军鼓 2闭镲 3开镲 4桶鼓
%        voice 1=kick 2=snare 3=hihat
%        -> 0→1, 1→2, 2→3, 3→3, 4→1
% ============================================================
    frames = uint8(frames);
    N = size(frames,1);
    ev = struct('time_s',{}, 'inst',{}, 'event',{}, 'chan',{}, ...
                'code',{}, 'vel',{}, 'dur_s',{}, 'ok',{});

    for i = 1:N
        f = frames(i,:);
        chk = 0;
        for k = 1:11, chk = bitxor(chk, double(f(k))); end
        e.ok     = (chk == double(f(12)));
        e.inst   = bitshift(bitand(f(3), 192), -6);      % bit7:6
        e.event  = bitand(bitshift(f(3), -4), 1);        % bit4  0=按下/触发 1=松开
        e.chan   = bitand(f(3), 15);                     % bit3:0
        ts       = double(f(5)) + 256*double(f(6));
        e.time_s = ts * 0.005;
        raw      = double(f(7)) + 256*double(f(8));
        if raw >= 32768, raw = raw - 65536; end          % int16 补码还原
        e.code   = raw;
        e.vel    = double(f(9)) + 256*double(f(10));     % uint16
        e.dur_s  = double(f(11)) * 0.05;
        ev(i)    = e;
    end
end
