%% =========================================================
%  demo_ensemble.m —— 协议 v1 端到端合奏 demo（钢琴 + 鼓）
%
%  链路：曲谱 → protocol_pack(打包成 12 字节帧) → 写 .bin
%        → protocol_unpack(解包校验) → 32 声部定点引擎渲染 → wav + 时域图
%
%  这样跑一遍，等于同时验证了三件事：
%    1) B 的鼓与 A 的钢琴能按同一套协议共存
%    2) 协议编解码与校验算法正确（队长/C 可直接复用）
%    3) 32 声部定点引擎在真实曲谱下不削波
%
%  运行：在本目录执行 demo_ensemble
% =========================================================
clear; clc;
addpath('lib');

%% ---------- 0. 先验证队长的 test_frames.bin ----------
A_BIN = '../../../sim/teamA/test_frames.bin';
if exist(A_BIN, 'file')
    fid = fopen(A_BIN, 'rb');
    raw = fread(fid, inf, 'uint8');
    fclose(fid);
    fr = reshape(raw, 12, [])';
    evA = protocol_unpack(fr);
    fprintf('=== 队长 test_frames.bin 校验（%d 帧）===\n', size(fr,1));
    for i = 1:numel(evA)
        sok = '失败'; if evA(i).ok, sok = '通过'; end
        fprintf('  帧%d t=%.0fms inst=%d code=%d vel=%d dur=%.2fs  校验%s\n', ...
            i, evA(i).time_s*1000, evA(i).inst, evA(i).code, ...
            evA(i).vel, evA(i).dur_s, sok);
    end
    sall = '有误'; if all([evA.ok]), sall = '通过'; end
    fprintf('  全部校验%s\n\n', sall);
end

%% ---------- 1. 曲谱 [time_s, inst, code, vel(0-127), dur_s] ----------
% inst: 0=钢琴 1=鼓   code: 钢琴=MIDI音高  鼓=0底鼓/1军鼓/2闭镲/3开镲/4桶鼓
score = [
    0.00  0  60  100  0.50 ;   % 钢琴 C4
    0.00  1   0  110  0.10 ;   % 底鼓
    0.25  0  64   95  0.45 ;   % 钢琴 E4
    0.50  0  67   95  0.45 ;   % 钢琴 G4
    0.50  1   1   90  0.10 ;   % 军鼓
    0.75  1   2   70  0.05 ;   % 闭镲
    1.00  0  72  105  0.60 ;   % 钢琴 C5
    1.00  1   0  110  0.10 ;   % 底鼓
    1.25  1   2   70  0.05 ;
    1.50  0  71   90  0.45 ;   % 钢琴 B4
    1.50  1   1   90  0.10 ;   % 军鼓
    1.75  1   2   75  0.05 ;
    2.00  0  67   95  0.50 ;   % 钢琴 G4
    2.00  1   0  115  0.10 ;
    2.25  1   2   70  0.05 ;
    2.50  0  64   90  0.45 ;
    2.50  1   1   90  0.10 ;
    2.75  1   3   80  0.30 ;   % 开镲
    3.00  0  60  100  0.80 ;   % 钢琴 C4 收尾
    3.00  1   0  110  0.10 ;
];

%% ---------- 2. 打包 → 写 bin → 解包（自检链路）----------
frames = protocol_pack(score);
fid = fopen('audio/ensemble_frames.bin','wb');
fwrite(fid, frames', 'uint8');
fclose(fid);

ev = protocol_unpack(frames);
assert(all([ev.ok]), '协议校验失败！');
fprintf('=== 打包自检：%d 帧，往返一致，校验全通过 ===\n\n', size(frames,1));

%% ---------- 3. 定点引擎渲染 ----------
[P, sine_rom, noise_rom] = init_engine('params');
roms = struct('sine', sine_rom, 'noise', noise_rom);
Fs = P.fs; PB = P.pb;

DRUM2VOICE = [1 2 3 3 1];      % 协议鼓件编码 -> voice 类型（关键映射！）

DUR = 3.9;
T = round(DUR * Fs);
V = voice_init(32);

% 事件按时间排序，并生成 note_off
noteoff = [];
for i = 1:numel(ev)
    if ev(i).inst == 0 && ev(i).dur_s > 0
        noteoff = [noteoff; ev(i).time_s + ev(i).dur_s, ev(i).code]; %#ok<AGROW>
    end
end

out = zeros(1, T);
eq = 1; nq = 1;
ev_t  = [ev.time_s]';
noteoff = sortrows(noteoff, 1);

for n = 1:T
    tn = n / Fs;
    while eq <= numel(ev) && tn >= ev_t(eq)
        e = ev(eq);
        vq = min(32767, bitshift(e.vel, -1));      % uint16 -> Q15
        if e.inst == 0
            [V, ch] = voice_noteon(V, e.code, vq, 4);          % 钢琴
            f = 440 * 2^((e.code - 69) / 12);
            V(ch).ftw = ftw_calc(f, PB, Fs);
        else
            vt = DRUM2VOICE(e.code + 1);
            [V, ~]  = voice_noteon(V, 0, vq, vt);               % 鼓
        end
        eq = eq + 1;
    end
    while nq <= size(noteoff,1) && tn >= noteoff(nq,1)
        V = voice_noteoff(V, noteoff(nq,2));
        nq = nq + 1;
    end
    acc = 0;
    for k = 1:32
        [s, V(k)] = voice_render(V(k), roms, P, 0);
        acc = acc + s;
    end
    % 混音：32 路求和 -> 饱和限幅 -> 留 15% 余量（与主脚本 dry 路径一致）
    out(n) = round(sat16(acc) * 0.85);
end

if ~exist('audio','dir'), mkdir('audio'); end
if ~exist('fig','dir'),   mkdir('fig');   end
audiowrite('audio/ensemble_demo.wav', int16(out), Fs);

%% ---------- 4. 时域图 ----------
figure('Name','钢琴+鼓合奏（协议 v1 驱动）','Position',[80 80 900 420]);
tp = (0:T-1)/Fs;
plot(tp, out); hold on;
plot(ev_t, 20000, 'r^', 'MarkerFaceColor','r');
xlabel('时间 (s)'); ylabel('幅度'); grid on;
title('合奏输出（红三角=演奏事件）');
print(gcf,'fig/ensemble_demo.png','-dpng','-r130');

%% ---------- 5. 汇总 ----------
npiano = sum([ev.inst] == 0);
ndrum  = sum([ev.inst] == 1);
fprintf('\n=== 合奏 demo 完成 ===\n');
fprintf('  事件：钢琴 %d 个 + 鼓 %d 个 = %d 帧\n', npiano, ndrum, numel(ev));
fprintf('  峰值 %d，削波 %d 个样本\n', max(abs(out)), sum(abs(out) >= 32767));
fprintf('  输出：audio/ensemble_demo.wav、audio/ensemble_frames.bin、fig/ensemble_demo.png\n');
