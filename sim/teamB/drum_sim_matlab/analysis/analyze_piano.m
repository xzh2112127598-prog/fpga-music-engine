%% analyze_piano.m
%  分析真实钢琴单音，验证队长参数：
%   3 谐波幅度比 1:0.35:0.12；衰减 tau 1.2/0.6/0.3s；起音 10ms
%  方法：STFT 分帧 -> 提取 f0/2f0/3f0 幅度轨迹 -> 拟合指数衰减
clear; clc; close all;

% 音名 -> 频率（A4=440）
note_map = containers.Map( ...
  {'A2','C4','D4','E4','G4','C5'}, ...
  {'A2','C4','D4','E4','G4','C5'});
freq_of = @(n) 440*2^((midi_of(n)-69)/12);
function m = midi_of(n)
  names = {'C','Cs','D','Ds','E','F','Fs','G','Gs','A','As','B'};
  pc = find(strcmp(names, n(1:end-1))) - 1;
  m = (str2double(n(end))+1)*12 + pc;
end
function f = fof(n)
  f = 440*2^((midi_of(n)-69)/12);
end

files = dir('samples/piano/*.wav');
res = struct();
for k = 1:length(files)
    nm = strrep(files(k).name,'.wav','');
    [x, sr] = audioread(fullfile(files(k).folder, files(k).name));
    if size(x,2)>1, x = mean(x,2); end
    x = x / max(abs(x)+eps);
    f0 = fof(nm);
    % STFT 分帧（帧长 = 8 个 f0 周期，hop 25%）
    flen = 2^nextpow2(round(8*sr/f0));
    hop = round(flen/4);
    nf = 1 + floor((length(x)-flen)/hop);
    tf = zeros(nf,3); tv = zeros(nf,3);
    for fr = 1:nf
        seg = x((fr-1)*hop+(1:flen)).*hann(flen);
        X = abs(fft(seg, flen));
        fc = (0:flen-1)*sr/flen;
        for h = 1:3
            target = h*f0;
            [~,ix] = max(X(abs(fc-target)<0.05*target));
            cand = find(abs(fc-target)<0.05*target);
            tv(fr,h) = X(cand(ix));
        end
        tf(fr) = ((fr-1)*hop + flen/2)/sr;
    end
    % 起音时间（f0 轨迹首次到 90% 峰值）
    [pk0, ipk] = max(tv(:,1));
    i90 = find(tv(1:ipk,1) >= 0.9*pk0, 1);
    attack = tf(i90);
    % 衰减拟合（峰值后，对数域线性）
    tau = zeros(1,3); amp0 = zeros(1,3);
    for h = 1:3
        seg_t = tv(ipk:end,h);
        seg_tt = tf(ipk:end);
        use = seg_t > 0.05*max(seg_t);     % 只用高于噪声部分
        p = polyfit(seg_tt(use), log(seg_t(use)), 1);
        tau(h) = -1/p(1);
        amp0(h) = seg_t(1);
    end
    amp_ratio = amp0/amp0(1);
    res.(nm) = struct('attack',attack,'tau',tau,'amp',amp_ratio);
    fprintf('%-3s 起音%.0fms | 幅度比 1:%.2f:%.2f | 衰减tau %.2f/%.2f/%.2fs\n', ...
        nm, attack*1000, amp_ratio(2), amp_ratio(3), tau(1), tau(2), tau(3));
end

% 汇总对比队长参数
fid = fopen('piano_extracted.md','w');
fprintf(fid,'# 真实钢琴谐波提取 vs 队长参数\n\n');
fprintf(fid,'队长目标：幅度比 1:0.35:0.12；衰减 1.2/0.6/0.3s；起音 10ms\n\n');
fprintf(fid,'| 音 | 起音ms | 幅度比(1:h2:h3) | tau(s) |\n|---|---|---|---|\n');
fns = fieldnames(res);
for k=1:length(fns)
    r = res.(fns{k});
    fprintf(fid,'| %s | %.0f | 1:%.2f:%.2f | %.2f/%.2f/%.2f |\n', ...
        fns{k}, r.attack*1000, r.amp(2), r.amp(3), r.tau(1), r.tau(2), r.tau(3));
end
fclose(fid);
disp('--- 写 piano_extracted.md ---');
