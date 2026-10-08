%% piano_36keys_C3_B5.m
% =====================================================================
%  36键钢琴音色仿真：C3 - B5（三个完整八度，共36键，含黑白键）
%
%  模型：非谐和性加性合成（Inharmonic Additive Synthesis）
%    · 每个键 = 基频 + 若干次泛音（harmonic series）叠加
%    · 泛音幅度按 1/k^1.8 递减（k 为谐波次数）
%    · 各次泛音独立指数衰减，高次泛音衰减更快（真实钢琴弦特征）
%    · 弦的非谐和性：f_k = k*f0*sqrt(1 + B*k^2)，B = 0.0003
%    · 双弦失谐 ±0.06% 产生轻微"拍频"，听感更真实
%    · 5 ms 线性起音包络模拟琴槌击弦
%
%  输出（全部保存在脚本所在目录）：
%    fig1_keyboard_C3_B5.png   键盘布局图（黑白键）
%    fig2_waveforms_C3_B5.png  全部键的波形图
%    fig3_spectra_C3_B5.png    全部键的频谱图（对数频率轴）
%    fig4_deepdive_C3_B5.png   典型音深挖：波形 + 频谱 + 语谱图
%    fig5_demo_spectrogram.png 依次演奏全键盘的语谱图
%    piano_demo_C3_B5.wav      依次演奏全部键（可直接听）
%    piano_notes_C3_B5\*.wav   每个键单独一个 wav
%
%  说明：范围 C3–B5 共 36 键（三个完整八度）；
%        如需含 C6（37键，12×3+1）把下面 endMidi 改成 84 即可。
% =====================================================================
clear; clc; close all;
tic;

%% ---------- 1. 全局参数 ----------
fs        = 48000;                % 采样率 (Hz) —— 与整机 48kHz 规格一致（I2S/时钟/LUT/FPGA）
noteDur   = 2.5;                  % 每个音符时长 (s)
startMidi = 48;                   % C3 的 MIDI 编号
endMidi   = 83;                   % B5 的 MIDI 编号（36键=三个完整八度 C3-B5）；如需含 C6 改为 84
% ---- FPGA 截断模式开关 ----
% fpgaMode = true ：只合成前 nHarmFPGA 个泛音，与 FPGA 可实现规格一致（对照验证用）
% fpgaMode = false：全泛音黄金参考模型（听感最真实，作为音色规格标准）
fpgaMode  = false;                % 默认关闭（保留全泛音黄金参考）
nHarmFPGA = 4;                    % FPGA 目标泛音数：8 voice×4 + 鼓8 = 40 振荡器（≥32 达标）
midis     = startMidi:endMidi;
nKeys     = numel(midis);

% 音名与黑白键判定（十二平均律音名表）
sharpName = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'};
keyNames  = cell(1,nKeys);
isBlack   = false(1,nKeys);
for i = 1:nKeys
    pc = mod(midis(i),12) + 1;
    keyNames{i} = sprintf('%s%d', sharpName{pc}, floor(midis(i)/12)-1);
    isBlack(i)  = any(pc == [2 4 7 9 11]);   % C# D# F# G# A# 为黑键
end

%% ---------- 2. 音高 -> 频率（十二平均律，A4=440Hz） ----------
f0 = @(m) 440 * 2.^((m-69)/12);

%% ---------- 3. 合成每个键 ----------
t     = (0:round(noteDur*fs)-1)/fs;   % 行向量
notes = cell(1,nKeys);

if fpgaMode
    fprintf('模式：FPGA 截断（每键前 %d 个泛音，与 FPGA 规格一致）\n', nHarmFPGA);
else
    fprintf('模式：黄金参考（全泛音，听感最真实）\n');
end
fprintf('正在合成 %d 个键 (%s - %s) ...\n', nKeys, keyNames{1}, keyNames{end});
for i = 1:nKeys
    f0i   = f0(midis(i));
    nHarm = min(64, floor((fs/2*0.9)/f0i));   % 泛音个数：低频多、高频受奈奎斯特限制
    if fpgaMode
        nHarm = min(nHarm, nHarmFPGA);        % FPGA 截断模式：只取前 N 个泛音
    end
    y = zeros(size(t));
    for k = 1:nHarm
        fk  = k*f0i*sqrt(1 + 0.0003*k^2);     % 非谐和泛音频率
        if fk > fs/2 - 100, break; end
        amp = k^-1.8;                         % 泛音幅度 ~ 1/k^1.8
        tau = (noteDur/(0.5 + f0i/280)) / k^0.7;   % 衰减时间：低音长、低次泛音长
        d   = 6e-4;                           % 双弦失谐比例
        y = y + amp*( exp(-t/tau).*sin(2*pi*fk*(1+d)*t) ...
                    + exp(-t/tau).*sin(2*pi*fk*(1-d)*t) )/2;
    end
    y = y/max(abs(y));
    % 起音包络：5 ms 线性上升（模拟琴槌击弦）
    r = max(2, round(0.005*fs));
    y(1:r) = y(1:r) .* ((0:r-1)/(r-1));
    % 结尾 30 ms 淡出，避免爆音
    fd = round(0.03*fs);
    y(end-fd+1:end) = y(end-fd+1:end) .* ((fd-1:-1:0)/(fd-1));
    notes{i} = y;
    fprintf('  %-4s  %8.2f Hz   %d 次泛音\n', keyNames{i}, f0i, nHarm);
end

%% ---------- 4. 预计算频谱（Hann 窗 + FFT，无工具箱依赖） ----------
Lsig = numel(notes{1});
win  = 0.5 - 0.5*cos(2*pi*(0:Lsig-1)'/(Lsig-1));   % Hann 窗（列向量）
Nfft = 2^nextpow2(Lsig);
freq = (0:Nfft/2-1)*fs/Nfft;                       % 行向量
spec = cell(1,nKeys);                              % 归一化 dB 谱
for i = 1:nKeys
    X   = abs(fft(notes{i}(:).*win, Nfft));
    X   = X(1:Nfft/2);
    spec{i} = 20*log10(X/max(X) + eps);
end

% 波形显示窗口（前 1.2 s）
tWin = (0:round(min(1.2,noteDur)*fs)-1)/fs;

%% ---------- 5. 图1：键盘布局（黑白键） ----------
fig1 = figure('Name','键盘布局','Color','w','Position',[40 60 1500 380]);
whiteX = zeros(1,nKeys); wc = 0; prevWX = -1;
for i = 1:nKeys
    if ~isBlack(i)
        wc = wc + 1; whiteX(i) = wc - 1; prevWX = whiteX(i);
    else
        whiteX(i) = prevWX + 0.62;
    end
end
hold on;
for i = 1:nKeys
    if ~isBlack(i)
        rectangle('Position',[whiteX(i) 0 0.92 1],'FaceColor','w','EdgeColor','k','LineWidth',1);
        text(whiteX(i)+0.46, -0.14, keyNames{i},'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    else
        rectangle('Position',[whiteX(i) 0 0.56 0.62],'FaceColor','k','EdgeColor','k','LineWidth',1);
        text(whiteX(i)+0.28, 0.28, keyNames{i},'HorizontalAlignment','center','Color','w','FontSize',7.5,'FontWeight','bold');
    end
end
axis equal; xlim([-0.6 wc+0.3]); ylim([-0.35 1.3]); axis off;
title(sprintf('钢琴键盘  %s - %s  （共 %d 键：%d 白键 / %d 黑键）', keyNames{1}, keyNames{end}, nKeys, wc, nKeys-wc),'FontSize',12);

%% ---------- 6. 图2：全部键的波形 ----------
fig2 = figure('Name','波形图','Color','w','Position',[50 60 1500 950]);
rows = ceil(sqrt(nKeys)); cols = ceil(nKeys/rows);
for i = 1:nKeys
    subplot(rows,cols,i);
    plot(tWin, notes{i}(1:numel(tWin)),'Color',[0 0.35 0.7],'LineWidth',0.5);
    title(keyNames{i},'FontSize',8);
    ylim([-1.15 1.15]);
    set(gca,'FontSize',7,'XTickLabel',[],'YTickLabel',[]);
    if i > nKeys-cols, xlabel('t (s)','FontSize',7); end
end
sgtitle(sprintf('%s-%s 全部 %d 键的波形（前 1.2 s）', keyNames{1}, keyNames{end}, nKeys),'FontSize',13);

%% ---------- 7. 图3：全部键的频谱 ----------
fig3 = figure('Name','频谱图','Color','w','Position',[60 60 1500 950]);
for i = 1:nKeys
    subplot(rows,cols,i);
    semilogx(freq, spec{i},'Color',[0.8 0.15 0.15],'LineWidth',0.5);
    xlim([f0(midis(i))/1.5, min(fs/2, f0(midis(i))*60)]);
    ylim([-90 0]); grid on;
    title(keyNames{i},'FontSize',8);
    set(gca,'FontSize',7,'YTick',[-60 -30 0]);
    if i > nKeys-cols, xlabel('频率 (Hz)','FontSize',7); end
end
sgtitle(sprintf('%s-%s 全部 %d 键的频谱（归一化 dB，对数频率轴）', keyNames{1}, keyNames{end}, nKeys),'FontSize',13);

%% ---------- 8. 图4：典型音深挖（低音/低音黑键/中央参考/高音） ----------
a4 = find(strcmp(keyNames,'A4')); if isempty(a4), a4 = round(nKeys/2); end
deepIdx = [1 2 a4 nKeys];
fig4 = figure('Name','典型音深挖','Color','w','Position',[70 60 1500 1000]);
for j = 1:4
    i = deepIdx(j);
    % 波形
    subplot(4,3,3*j-2);
    plot(tWin, notes{i}(1:numel(tWin)),'Color',[0 0.35 0.7],'LineWidth',0.6);
    title(sprintf('%s  波形（f0=%.1f Hz）', keyNames{i}, f0(midis(i))),'FontSize',9);
    xlabel('t (s)','FontSize',8); ylim([-1.15 1.15]);
    % 频谱
    subplot(4,3,3*j-1);
    semilogx(freq, spec{i},'Color',[0.8 0.15 0.15],'LineWidth',0.6);
    xlim([f0(midis(i))/1.5, min(fs/2, f0(midis(i))*60)]);
    ylim([-90 0]); grid on;
    xlabel('频率 (Hz)','FontSize',8); set(gca,'FontSize',8,'YTick',[-60 -30 0]);
    % 语谱图（手动 STFT，避免工具箱依赖）
    S = stftMag(notes{i}(:), fs, 2048, 512);
    subplot(4,3,3*j);
    imagesc((0:size(S,2)-1)*512/fs, (0:size(S,1)-1)*fs/2048, 20*log10(S/max(S(:))+eps));
    axis xy; set(gca,'YScale','log','YLim',[f0(midis(i))/1.5, min(fs/2, f0(midis(i))*60)],'CLim',[-80 0]);
    colormap(jet); colorbar;
    xlabel('t (s)','FontSize',8); ylabel('频率 (Hz)','FontSize',8);
    title(sprintf('%s  语谱图', keyNames{i}),'FontSize',9);
end

%% ---------- 9. 图5：全键盘依次演奏的语谱图 ----------
demo = [];
gap  = zeros(round(0.12*fs),1);
for i = 1:nKeys
    demo = [demo; notes{i}(:); gap]; %#ok<AGROW>
end
fig5 = figure('Name','全键盘语谱图','Color','w','Position',[80 60 1500 420]);
Sd = stftMag(demo, fs, 4096, 1024);
imagesc((0:size(Sd,2)-1)*1024/fs, (0:size(Sd,1)-1)*fs/4096, 20*log10(Sd/max(Sd(:))+eps));
axis xy; set(gca,'YScale','log','YLim',[50 8000],'CLim',[-80 0]);
colormap(jet); colorbar;
xlabel('t (s)','FontSize',10); ylabel('频率 (Hz)','FontSize',10);
title(sprintf('%s-%s 全部 %d 键依次演奏（每音约 %.1f s）', keyNames{1}, keyNames{end}, nKeys, noteDur+0.12),'FontSize',12);

%% ---------- 10. 保存图片与音频 ----------
outDir = 'piano_notes_C3_B5';
if ~exist(outDir,'dir'), mkdir(outDir); end
print(fig1,'-dpng','-r150','fig1_keyboard_C3_B5.png');
print(fig2,'-dpng','-r150','fig2_waveforms_C3_B5.png');
print(fig3,'-dpng','-r150','fig3_spectra_C3_B5.png');
print(fig4,'-dpng','-r150','fig4_deepdive_C3_B5.png');
print(fig5,'-dpng','-r150','fig5_demo_spectrogram.png');

audiowrite('piano_demo_C3_B5.wav', demo, fs);
for i = 1:nKeys
    audiowrite(fullfile(outDir, sprintf('%s.wav', keyNames{i})), notes{i}(:), fs);
end

fprintf('\n完成！总耗时 %.1f s\n', toc);
fprintf('图片：当前目录 fig1~fig5_*.png\n');
fprintf('音频：piano_demo_C3_B5.wav（全键盘演示）；piano_notes_C3_B5\\ 目录下 %d 个单键 wav\n', nKeys);

%% ---------- 本地函数：手动 STFT（幅度谱） ----------
function S = stftMag(x, fs, winLen, hop)
    n = numel(x);
    win = 0.5 - 0.5*cos(2*pi*(0:winLen-1)'/(winLen-1));   % Hann 窗（列向量）
    nFrames = max(1, floor((n-winLen)/hop) + 1);
    S = zeros(winLen/2+1, nFrames);
    for j = 1:nFrames
        seg = x((j-1)*hop+1 : (j-1)*hop+winLen) .* win;
        fseg = abs(fft(seg));
        S(:,j) = fseg(1:winLen/2+1);   % 只取正频率一半
    end
end
