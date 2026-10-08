function piano_check()
% piano_check.m —— 无界面运行版（COM 自动化验证用）
% 与 piano_36keys_C3_C6.m 的合成与出图逻辑完全一致，仅差异：
%   1) 函数封装，不污染调用者工作区；
%   2) 不执行 clear/clc/close all，不关闭已有图窗；
%   3) 所有图窗不可见（Visible=off），不弹窗，仍正常保存 PNG。
% 说明：范围 C3–B5 共 36 键（三个完整八度）；如需含 C6（37键）把 endMidi 改为 84。
tic;

%% ---------- 1. 全局参数 ----------
fs        = 44100;
noteDur   = 2.5;
startMidi = 48;
endMidi   = 83;   % B5（36键=三个完整八度 C3-B5）；如需含 C6 改为 84
midis     = startMidi:endMidi;
nKeys     = numel(midis);

sharpName = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'};
keyNames  = cell(1,nKeys);
isBlack   = false(1,nKeys);
for i = 1:nKeys
    pc = mod(midis(i),12) + 1;
    keyNames{i} = sprintf('%s%d', sharpName{pc}, floor(midis(i)/12)-1);
    isBlack(i)  = any(pc == [2 4 7 9 11]);
end

%% ---------- 2. 音高 -> 频率 ----------
f0 = @(m) 440 * 2.^((m-69)/12);

%% ---------- 3. 合成 ----------
t     = (0:round(noteDur*fs)-1)/fs;
notes = cell(1,nKeys);
fprintf('正在合成 %d 个键 (%s - %s) ...\n', nKeys, keyNames{1}, keyNames{end});
for i = 1:nKeys
    f0i   = f0(midis(i));
    nHarm = min(64, floor((fs/2*0.9)/f0i));
    y = zeros(size(t));
    for k = 1:nHarm
        fk  = k*f0i*sqrt(1 + 0.0003*k^2);
        if fk > fs/2 - 100, break; end
        amp = k^-1.8;
        tau = (noteDur/(0.5 + f0i/280)) / k^0.7;
        d   = 6e-4;
        y = y + amp*( exp(-t/tau).*sin(2*pi*fk*(1+d)*t) ...
                    + exp(-t/tau).*sin(2*pi*fk*(1-d)*t) )/2;
    end
    y = y/max(abs(y));
    r = max(2, round(0.005*fs));
    y(1:r) = y(1:r) .* ((0:r-1)/(r-1));
    fd = round(0.03*fs);
    y(end-fd+1:end) = y(end-fd+1:end) .* ((fd-1:-1:0)/(fd-1));
    notes{i} = y;
    fprintf('  %-4s  %8.2f Hz   %d 次泛音\n', keyNames{i}, f0i, nHarm);
end

%% ---------- 4. 频谱 ----------
Lsig = numel(notes{1});
win  = 0.5 - 0.5*cos(2*pi*(0:Lsig-1)'/(Lsig-1));
Nfft = 2^nextpow2(Lsig);
freq = (0:Nfft/2-1)*fs/Nfft;
spec = cell(1,nKeys);
for i = 1:nKeys
    X   = abs(fft(notes{i}(:).*win, Nfft));
    X   = X(1:Nfft/2);
    spec{i} = 20*log10(X/max(X) + eps);
end
tWin = (0:round(min(1.2,noteDur)*fs)-1)/fs;

%% ---------- 5. 图1：键盘布局 ----------
fig1 = figure('Visible','off','Name','键盘布局','Color','w','Position',[40 60 1500 380]);
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

%% ---------- 6. 图2：波形 ----------
fig2 = figure('Visible','off','Name','波形图','Color','w','Position',[50 60 1500 950]);
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

%% ---------- 7. 图3：频谱 ----------
fig3 = figure('Visible','off','Name','频谱图','Color','w','Position',[60 60 1500 950]);
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

%% ---------- 8. 图4：典型音深挖 ----------
a4 = find(strcmp(keyNames,'A4')); if isempty(a4), a4 = round(nKeys/2); end
deepIdx = [1 2 a4 nKeys];
fig4 = figure('Visible','off','Name','典型音深挖','Color','w','Position',[70 60 1500 1000]);
for j = 1:4
    i = deepIdx(j);
    subplot(4,3,3*j-2);
    plot(tWin, notes{i}(1:numel(tWin)),'Color',[0 0.35 0.7],'LineWidth',0.6);
    title(sprintf('%s  波形（f0=%.1f Hz）', keyNames{i}, f0(midis(i))),'FontSize',9);
    xlabel('t (s)','FontSize',8); ylim([-1.15 1.15]);
    subplot(4,3,3*j-1);
    semilogx(freq, spec{i},'Color',[0.8 0.15 0.15],'LineWidth',0.6);
    xlim([f0(midis(i))/1.5, min(fs/2, f0(midis(i))*60)]);
    ylim([-90 0]); grid on;
    xlabel('频率 (Hz)','FontSize',8); set(gca,'FontSize',8,'YTick',[-60 -30 0]);
    S = stftMag(notes{i}(:), fs, 2048, 512);
    subplot(4,3,3*j);
    imagesc((0:size(S,2)-1)*512/fs, (0:size(S,1)-1)*fs/2048, 20*log10(S/max(S(:))+eps));
    axis xy; set(gca,'YScale','log','YLim',[f0(midis(i))/1.5, min(fs/2, f0(midis(i))*60)],'CLim',[-80 0]);
    colormap(jet); colorbar;
    xlabel('t (s)','FontSize',8); ylabel('频率 (Hz)','FontSize',8);
    title(sprintf('%s  语谱图', keyNames{i}),'FontSize',9);
end

%% ---------- 9. 图5：全键盘语谱图 ----------
demo = [];
gap  = zeros(round(0.12*fs),1);
for i = 1:nKeys
    demo = [demo; notes{i}(:); gap]; %#ok<AGROW>
end
fig5 = figure('Visible','off','Name','全键盘语谱图','Color','w','Position',[80 60 1500 420]);
Sd = stftMag(demo, fs, 4096, 1024);
imagesc((0:size(Sd,2)-1)*1024/fs, (0:size(Sd,1)-1)*fs/4096, 20*log10(Sd/max(Sd(:))+eps));
axis xy; set(gca,'YScale','log','YLim',[50 8000],'CLim',[-80 0]);
colormap(jet); colorbar;
xlabel('t (s)','FontSize',10); ylabel('频率 (Hz)','FontSize',10);
title(sprintf('%s-%s 全部 %d 键依次演奏（每音约 %.1f s）', keyNames{1}, keyNames{end}, nKeys, noteDur+0.12),'FontSize',12);

%% ---------- 10. 保存 ----------
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
fprintf('音频：piano_demo_C3_B5.wav；piano_notes_C3_B5\\ 目录下 %d 个单键 wav\n', nKeys);

end

%% ---------- 本地函数：手动 STFT ----------
function S = stftMag(x, fs, winLen, hop)
    n = numel(x);
    win = 0.5 - 0.5*cos(2*pi*(0:winLen-1)'/(winLen-1));
    nFrames = max(1, floor((n-winLen)/hop) + 1);
    S = zeros(winLen/2+1, nFrames);
    for j = 1:nFrames
        seg = x((j-1)*hop+1 : (j-1)*hop+winLen) .* win;
        fseg = abs(fft(seg));
        S(:,j) = fseg(1:winLen/2+1);   % 只取正频率一半
    end
end
