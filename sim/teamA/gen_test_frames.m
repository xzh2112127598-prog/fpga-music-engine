%% gen_test_frames.m —— 生成协议 v1 测试帧（3 帧：钢琴C4 → 钢琴E4 → 鼓Kick）
%  用途：10.4 联调时运行，生成 test_frames.bin 发给 C 的 serial_player 播放；
%        能听到按时间戳排好的"叮-叮-咚"即证明协议 v1 与数据通路成立。
%  用法：MATLAB 里 F5 运行。
clear; clc;

frames = [
    0xAA 0x55 0x00 0x00 0x00 0x00 0x3C 0x00 0x00 0x80 0x0A 0x00;  % 0ms    钢琴 中央C MIDI60
    0xAA 0x55 0x00 0x00 0x64 0x00 0x40 0x00 0x00 0x80 0x0A 0x00;  % 500ms  钢琴 E4  MIDI64
    0xAA 0x55 0x41 0x00 0xC8 0x00 0x00 0x00 0x00 0x80 0x02 0x00;  % 1000ms 鼓 Kick
];

for i = 1:size(frames, 1)          % 自动计算第 12 字节异或校验
    frames(i, 12) = 0;
    for k = 1:11
        frames(i, 12) = bitxor(frames(i, 12), frames(i, k));
    end
end

fid = fopen('test_frames.bin', 'wb');
fwrite(fid, frames', 'uint8');     % 按帧顺序写出 36 字节
fclose(fid);

disp('test_frames.bin 已生成（36 字节，3 帧）');
disp('联调：把该文件发给 C 的 serial_player 播放；');
disp('或取消下面注释直接串口发送（把 COM3 改成实际串口号）：');
% s = serialport('COM3', 115200);
% write(s, frames', 'uint8');
