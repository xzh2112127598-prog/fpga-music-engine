function [v, ch] = voice_noteon(v, note, vel, type)
% VOICE_NOTEON 分配一个声部给新音符
%   优先找空闲(state=0)；32路全忙时窃取“最老”声部（age最大）
ch = find([v.state] == 0, 1);
if isempty(ch)
    [~, ch] = max([v.age]);
end
v(ch).state = 1;  v(ch).note = note;  v(ch).vel = vel;  v(ch).type = type;
v(ch).phase = 0;  v(ch).phase2 = 0;  v(ch).phase3 = 0;  v(ch).nphase = 0;
v(ch).f1 = 0;     v(ch).f2 = 0;      v(ch).f3 = 0;      v(ch).f4 = 0;
v(ch).sidx = 0;   v(ch).lfo = 0;
v(ch).env = 0;    v(ch).env2 = 0;    v(ch).env3 = 0;    v(ch).age = 0;
end
