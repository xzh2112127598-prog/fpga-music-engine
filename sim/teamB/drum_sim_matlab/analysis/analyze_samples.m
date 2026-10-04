%% analyze_samples.m
%  分析真实鼓/钢琴样本，提取【频率峰值、衰减时间常数、频带能量、时长】
%  仅用于校准合成参数；不把样本送入 FPGA。
%  运行：在 analysis 目录 F5
clear; clc; close all;
Fs = 48000;

function info = analyze_one(fname)
    [x, sr] = audioread(fname);
    if size(x,2) > 1, x = mean(x,2); end      % 单声道
    x = x / max(abs(x)+eps);                  % 归一化
    N = length(x);
    % --- 包络（滑动窗 RMS，窗10ms）---
    w = max(8, round(0.01*sr));
    env = sqrt(movmean(x.^2, w));
    [~,i0] = max(env);
    % 找包络衰减到 10% 的时间 -> 估计衰减时间常数 tau
    tail = env(i0:end);
    idx10 = find(tail < 0.1*max(tail), 1);
    if isempty(idx10), tau = NaN; dur = N/sr;
    else
        dur = (i0+idx10)/sr;
        % 指数衰减: env = exp(-t/tau)，降到0.1 => tau = t/ln(10)
        tau = (idx10/sr)/log(10);
    end
    % --- 攻击瞬态频谱（起音后 5~30ms）---
    a1 = i0 + round(0.005*sr);
    a2 = min(N, i0 + round(0.03*sr));
    seg = x(a1:a2).*hann(a2-a1+1);
    X = abs(fft(seg, 2^nextpow2(4*sr)));
    fv = (0:length(X)-1)'*sr/length(X);
    X = X(1:end/2); fv = fv(1:end/2);
    % 峰值频率（分低频段<300 和 高频段>1000）
    [~,il] = max(X(fv<400));
    flo = fv(fv<400); fpeak_lo = flo(il);
    [~,ih] = max(X(fv>1000));
    fh = fv(fv>1000); fpeak_hi = fh(ih);
    % 频带能量占比
    el = sum(X(fv<500).^2);
    em = sum(X(fv>=500 & fv<4000).^2);
    eh = sum(X(fv>=4000).^2);
    et = el+em+eh+eps;
    info = struct('name',fname,'sr',sr,'dur',N/sr,'tau',tau, ...
        'f_lo',fpeak_lo,'f_hi',fpeak_hi, ...
        'p_lo',el/et,'p_mid',em/et,'p_hi',eh/et);
end

%% 分析全部鼓样本
dd = 'samples/drum';
files = dir(fullfile(dd,'*.wav'));
infos = [];
for k = 1:length(files)
    in = analyze_one(fullfile(dd,files(k).name));
    infos = [infos; in];
    [~,short] = fileparts(files(k).name);
    fprintf('%-14s 时长%.2fs tau%.3fs 低频峰%5.0fHz 高频峰%5.0fHz 能量 低%.2f 中%.2f 高%.2f\n', ...
        short, in.dur, in.tau, in.f_lo, in.f_hi, in.p_lo, in.p_mid, in.p_hi);
end

%% 钢琴样本（若有）
if exist('samples/piano','dir')
    pf = dir(fullfile('samples/piano','*.wav'));
    for k = 1:length(pf)
        in = analyze_one(fullfile('samples/piano',pf(k).name));
        fprintf('钢琴 %-12s 时长%.2fs tau%.3fs 低频峰%5.0fHz\n', pf(k).name, in.dur, in.tau, in.f_lo);
    end
end

%% 写提取结果
fid = fopen('extracted_params.md','w');
fprintf(fid,'# 真实样本提取参数（校准参考）\n\n');
fprintf(fid,'| 样本 | 时长s | 衰减tau s | 低频峰Hz | 高频峰Hz | 低/中/高能量 |\n|---|---|---|---|---|---|\n');
for k=1:length(infos)
    [~,nm] = fileparts(infos(k).name);
    fprintf(fid,'| %s | %.2f | %.3f | %.0f | %.0f | %.2f/%.2f/%.2f |\n', ...
        nm, infos(k).dur, infos(k).tau, infos(k).f_lo, infos(k).f_hi, ...
        infos(k).p_lo, infos(k).p_mid, infos(k).p_hi);
end
fclose(fid);
disp('--- 提取结果已写 extracted_params.md ---');
