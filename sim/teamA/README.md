# 队员 A · 音频核心引擎仿真

负责人：队员 A

## 交付位

- `piano_synth.m` —— 十二平均律钢琴单音加法合成（基频 + 2/3 次谐波）
- 生成的 12 个单音 wav（或 1 个含 12 音的演示文件）+ 波形/频谱图
- `sine_lut.mi` / `.hex`、`note_freq.mi`、`env_lut.mi`

## 必须遵守的统一口径（队长 2026-10-04）

| 项 | 值 |
|---|---|
| 采样率 | 48000 Hz |
| 样本 | int16（Q15） |
| 频率字 | `freq_word = round(f × 2^32 / 48000)` ← **32bit，不是 24bit** |
| 每 voice 谐波 | 3 个独立振荡器，幅度比 `1 : 0.35 : 0.12` |
| 包络时间常数 | 基频 1.2 s、2 次 0.6 s、3 次 0.3 s |
| 起音 | 10 ms |

> MIDI 0–127 的频率与 32bit 频率字已由队员 B 生成，直接用：
> `sim/teamB/drum_sim_matlab/params/note_freq.md`
> 该文件由 `lib/init_engine.m` 自动生成，**不要手改，改参数改 init_engine.m**。

## 需要 A 交付给 B 的东西

- 钢琴音色定稿后，替换 `main_drum_engine.m` 中临时的钢琴排程（声部框架不变）
- 《演奏数据包协议 v1》落到 `doc/protocol_v1.md`，B 的合奏 demo 依赖它
