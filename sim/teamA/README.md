# sim/teamA —— 队长：钢琴仿真与 LUT

## 目录说明

- piano_synth.m        钢琴加法合成（每谐波独立包络），输出 demo_piano.wav / single_C4.wav / piano_plots.png
- gen_lut.m            生成三张 LUT 表（正弦表 / 频率表 / 包络表），.mi 与 .hex 两种格式
- gen_test_frames.m    生成协议 v1 三帧测试文件 test_frames.bin（10.5 联调用）
- protocol_v1.md       演奏数据包协议 v1（正式版放 doc/）

## 验收记录（2026-10-04）

- [x] 仿真通过：C4 频谱峰值 261.5 Hz，理论 261.6 Hz，误差 0.06%（要求 <0.5%）
- [x] 试听通过：谐波独立包络优化后音色圆润、无爆音
- [x] 表文件齐全：sine_lut（1024 行）、note_freq（128 行）、env_lut（256 行），.mi/.hex 各一份
- [x] 协议 v1 落盘 doc/protocol_v1.md，待 10.4 联调冻结
- [ ] 联调：test_frames.bin 由 C 的 serial_player 完整播出、无错帧（待 10.45完成）

## 对 FPGA 的关键参数（供 B 参考）

- 采样率 48 kHz；样本 int16
- 钢琴每 voice 3 个谐波振荡器，幅度比 1 : 0.35 : 0.12
- 包络时间常数：基频 1.2 s、2 次谐波 0.6 s、3 次谐波 0.3 s，起音 10 ms
- 频率字：freq_word = round( f × 2^32 / 48000 )，MIDI 0–127 见 note_freq 表

