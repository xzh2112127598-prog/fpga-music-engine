function [s, vk] = voice_render(vk, roms, P, bend_id)
% VOICE_RENDER 单声部单样本定点渲染（硬件：该声部全部振荡器 + 包络）
%   type 1=kick 2=snare 3=hihat 4=piano
s = 0;
if vk.state == 0, return; end

PB = P.pb; WRAP = 2^PB;
SS = P.sine_shift;            % 正弦表地址移位：32-10=22
NS = P.noise_shift;           % 噪声表地址移位：32-13=19

% ---- LFO（低频 DDS，颤音）----
vk.lfo = vk.lfo + P.lfo_ftw;
if vk.lfo >= WRAP, vk.lfo = vk.lfo - WRAP; end
lfo = roms.sine(floor(vk.lfo / 2^SS) + 1);

% ---- 弯音 ratio（查表 + LFO 偏移）----
ratio = P.bend_tbl(bend_id + 21);
ratio = ratio + q15mul(lfo, P.lfo_depth(vk.type));

switch vk.type
    case 1   % ===== KICK：扫频正弦 + 攻击 click =====
        vk.sidx = vk.sidx + 1;
        si = min(255, floor(vk.sidx / P.kick_n * 256));
        ftw = q15mul(P.kick_sweep(si+1), ratio);
        vk.phase = vk.phase + ftw;
        if vk.phase >= WRAP, vk.phase = vk.phase - WRAP; end
        body = lut_ip(roms.sine, vk.phase, SS);
        % 攻击 click（鼓槌击皮高频瞬态，仅前 click_n 样本）
        vk.nphase = vk.nphase + P.noise_ftw;
        if vk.nphase >= WRAP, vk.nphase = vk.nphase - WRAP; end
        nraw = roms.noise(floor(vk.nphase / 2^NS) + 1);
        vk.f4 = vk.f4 + floor(P.lp3k * (nraw - vk.f4));
        click = 0;
        if vk.sidx <= P.click_n, click = vk.f4; end
        s = round(0.6*body) + round(0.2*click);

    case 2   % ===== SNARE：180/200 膜主体 + 5~9kHz 响弦噪声 =====
        vk.phase  = vk.phase  + q15mul(ftw_calc(180,PB,P.fs), ratio);
        vk.phase2 = vk.phase2 + q15mul(ftw_calc(200,PB,P.fs), ratio);
        if vk.phase  >= WRAP, vk.phase  = vk.phase  - WRAP; end
        if vk.phase2 >= WRAP, vk.phase2 = vk.phase2 - WRAP; end
        body = round(0.5*lut_ip(roms.sine,vk.phase,SS) ...
                   + 0.3*lut_ip(roms.sine,vk.phase2,SS));
        % 噪声带通 5~9kHz（低通9k + 高通5k）
        vk.nphase = vk.nphase + P.noise_ftw;
        if vk.nphase >= WRAP, vk.nphase = vk.nphase - WRAP; end
        nraw = roms.noise(floor(vk.nphase / 2^NS) + 1);
        vk.f1 = vk.f1 + floor(P.lp9k * (nraw - vk.f1));
        vk.f2 = floor(P.hp5k * (vk.f2 + vk.f1 - vk.f3));
        vk.f3 = vk.f1;
        s = round(0.35*body) + q15mul(vk.f2, round(0.5*32768));

    case 3   % ===== HIHAT：7~10kHz 噪声 + 金属共振正弦 =====
        vk.nphase = vk.nphase + P.noise_ftw;
        if vk.nphase >= WRAP, vk.nphase = vk.nphase - WRAP; end
        nraw = roms.noise(floor(vk.nphase / 2^NS) + 1);
        vk.f1 = vk.f1 + floor(P.lp10k * (nraw - vk.f1));
        vk.f2 = floor(P.hp7k * (vk.f2 + vk.f1 - vk.f3));
        vk.f3 = vk.f1;
        % 3 个非谐金属共振（6200/7900/9400Hz）
        vk.phase  = mod(vk.phase  + ftw_calc(6200,PB,P.fs), WRAP);
        vk.phase2 = mod(vk.phase2 + ftw_calc(7900,PB,P.fs), WRAP);
        vk.phase3 = mod(vk.phase3 + ftw_calc(9400,PB,P.fs), WRAP);
        m1 = roms.sine(floor(vk.phase /2^SS)+1);
        m2 = roms.sine(floor(vk.phase2/2^SS)+1);
        m3 = roms.sine(floor(vk.phase3/2^SS)+1);
        s = round(0.45*vk.f2) + round(0.08*(m1+m2+m3));

    case 4   % ===== PIANO：3 谐波加法合成（幅度 1:0.35:0.12）=====
        f = q15mul(vk.ftw, ratio);
        vk.phase  = vk.phase  + f;
        vk.phase2 = vk.phase2 + 2*f;
        vk.phase3 = vk.phase3 + 3*f;
        if vk.phase  >= WRAP, vk.phase  = vk.phase  - WRAP; end
        if vk.phase2 >= WRAP, vk.phase2 = vk.phase2 - WRAP; end
        if vk.phase3 >= WRAP, vk.phase3 = vk.phase3 - WRAP; end
        raw1 = lut_ip(roms.sine, vk.phase, SS);
        raw2 = q15mul(lut_ip(roms.sine, vk.phase2, SS), round(0.35*32768));
        raw3 = q15mul(lut_ip(roms.sine, vk.phase3, SS), round(0.12*32768));
        % 3 个独立包络
        [vk.env, vk.env2, vk.env3, vk.state] = piano_env( ...
            vk.env, vk.env2, vk.env3, vk.state, ...
            P.piano_khold, P.piano_krel, P.piano_attack);
        s = q15mul(raw1,vk.env) + q15mul(raw2,vk.env2) + q15mul(raw3,vk.env3);
end

% ---- 增益 + 力度 + 包络 ----
if vk.type <= 3
    s = q15mul(s, round(0.8*32768));
    s = q15mul(s, vk.vel);
    [vk.env, vk.state] = adsr_step(vk.env, vk.state, P.adsr(vk.type));
    s = q15mul(s, vk.env);
else
    s = q15mul(s, vk.vel);                 % 钢琴：包络已在内部
end
vk.age = vk.age + 1;
end
