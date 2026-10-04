function [env, state] = adsr_step(env, state, p)
% ADSR_STEP 单样本定点 ADSR 状态机（硬件：包络 FSM + 移位衰减）
%   p.attack_step : ATTACK 每样本增量
%   p.decay_k     : DECAY 右移位数（k越大衰减越慢）
%   p.sustain     : 保持电平 Q15（鼓=0）
%   p.release_k   : RELEASE 右移位数
%   衰减量用 max(1, floor(env/2^k))，防止 env<2^k 时死锁
switch state
    case 1                                  % ATTACK
        env = env + p.attack_step;
        if env >= 32767, env = 32767; state = 2; end
    case 2                                  % DECAY
        env = env - max(1, floor(env / 2^p.decay_k));
        if env <= p.sustain
            if p.sustain <= 0, env = 0; state = 0;     % 鼓：衰减到底，声放回空闲
            else, state = 3; end
        end
    case 3                                  % SUSTAIN
        env = p.sustain;
    case 4                                  % RELEASE
        env = env - max(1, floor(env / 2^p.release_k));
        if env <= 0, env = 0; state = 0; end
end
end
