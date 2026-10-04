% debug_hihat.m 复现 hihat 高通滤波 f1=-Inf
clear; clc; addpath('hwlib');
nr = make_noise_table(8192);
fprintf('noise rom 范围: %d ~ %d, 有限=%d\n', min(nr), max(nr), all(isfinite(nr)));

f1=0; f2=0; nphase=0; bad=0;
for k=1:10000
    nphase=nphase+2048;
    if nphase>=2^24, nphase=nphase-2^24; end
    ns = nr(floor(nphase/2^11)+1);
    f1 = f1 + floor(0.7854*(f1+ns-f2));
    f2 = ns;
    if ~isfinite(f1)
        fprintf('f1 异常于第 %d 样本: f1=%g, 上一f2=%g, ns=%g\n', k, f1, f2, ns);
        bad=1; break;
    end
end
if ~bad, fprintf('10000样本内 f1 正常, 最终 f1=%d\n', f1); end
