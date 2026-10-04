function [e1,e2,e3,state] = piano_env(e1,e2,e3,state, k_hold, k_rel, attack_step)
% PIANO_ENV 钢琴3谐波独立包络
%   state 1=ATTACK(10ms) 2=HOLD(按住，3谐波各自慢衰减) 4=RELEASE(松键，快速衰减)
%   k_hold 三个谐波按住衰减移位（16/15/14 -> tau 1.2/0.6/0.3s）
%   k_rel  松键衰减移位
switch state
    case 1                                  % ATTACK
        e1 = min(32767, e1 + attack_step);
        e2 = min(32767, e2 + attack_step);
        e3 = min(32767, e3 + attack_step);
        if e1 >= 32767, state = 2; end
    case 2                                  % HOLD（按住）
        e1 = e1 - max(1, floor(e1 / 2^k_hold(1)));
        e2 = e2 - max(1, floor(e2 / 2^k_hold(2)));
        e3 = e3 - max(1, floor(e3 / 2^k_hold(3)));
    case 4                                  % RELEASE（松键）
        e1 = e1 - max(1, floor(e1 / 2^k_rel));
        e2 = e2 - max(1, floor(e2 / 2^k_rel));
        e3 = e3 - max(1, floor(e3 / 2^k_rel));
        if e1 <= 0 && e2 <= 0 && e3 <= 0
            e1 = 0; e2 = 0; e3 = 0; state = 0;
        end
end
end
