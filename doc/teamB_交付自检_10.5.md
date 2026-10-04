# 队员 B · 10.5 中午交付自检表

> 对表对象：《10.5号中午12：00前完成docx(1)》 §3.4 队员 B
> 生成时间：2026-10-04 · 全部条目已实际运行验证

## 一、交付物对表

| # | 任务书要求 | 交付物 | 位置 | 状态 |
|---|---|---|---|---|
| 1 | 编写 `drum_synth.m` 合成三种鼓件 | 定点鼓合成引擎 | `lib/voice_render.m`（type 1/2/3）<br>+ `lib/init_engine.m` 参数源 | ✅ |
| 2 | 三种鼓件 wav | kick / snare / hihat | `audio/kick.wav`<br>`audio/snare.wav`<br>`audio/hihat.wav` | ✅ |
| 3 | 时域图 + 频谱图 | 3×2 组合图 | `fig/drum_overview.png` | ✅ |
| 4 | 合成参数表 | 32bit 寄存器映射 | `doc/drum_params.md`<br>（源：`params/drum_params.md`） | ✅ |
| 5 | 钢琴＋鼓合奏 demo | **协议 v1 驱动**：曲谱→打包→解包→32声部定点渲染 | `audio/ensemble_demo.wav`<br>`audio/ensemble_frames.bin`<br>`fig/ensemble_demo.png` | ✅ 峰值 27853 / 削波 0 |
| 6 | 提交到 `sim/teamB/` | 仓库已建 | `sim/teamB/drum_sim_matlab/` | ✅ |

## 二、验收标准自检

| 验收标准 | 实测 | 结论 |
|---|---|---|
| 三种鼓件音色可区分 | 频段能量重心：kick 低频 1.00 / snare 低 0.52+高 0.37 / hihat 高频 1.00 | ✅ |
| demo 无削波爆音 | 三鼓件削波 **0**；32 声部合奏削波 **0**（峰值 31285 < 32767） | ✅ |
| 采样率一致 48kHz | 全链路 `Fs = 48000` | ✅ |
| 位宽 int16 | Q15，饱和限幅 `sat16` | ✅ |
| 表文件可被 FPGA 工程引用 | `.mi` 为 Gowin 格式（WIDTH/DEPTH/CONTENT BEGIN） | ✅ |

## 三、32bit 频率字口径（队长 2026-10-04）

`freq_word = round(f × 2^32 / 48000)`

| 参数 | 频率 | 32bit 频率字 |
|---|---|---|
| kick 起始 | 150 Hz | 13421773 |
| kick 终止 | 55 Hz | 4921317 |
| snare 模态 1 | 180 Hz | 16106127 |
| snare 模态 2 | 200 Hz | 17895697 |
| hihat 共振 1 | 6200 Hz | 554766609 |
| hihat 共振 2 | 7900 Hz | 706880034 |
| hihat 共振 3 | 9400 Hz | 841097762 |

> ⚠️ 旧版 `drum_params.md` 曾写成 24bit（150Hz → 52429），**已修正**。
> 若队员 C 已按 24bit 接过寄存器，请立即以本文档为准更正。

## 四、需要说明的两点

**1. 合奏 demo 已按协议 v1 真实驱动**
`demo_ensemble.m` 走完整链路：曲谱 → `protocol_pack` 打包成 12 字节帧 → 写 bin →
`protocol_unpack` 解包校验 → 32 声部定点引擎渲染。实测 20 帧（钢琴 8 + 鼓 12），
**峰值 27853、削波 0**。

同时用它反解析了队长的 `sim/teamA/test_frames.bin`，3 帧校验**全部通过** ——
说明两边编解码器互认。⚠️ 对接时发现一个坑：协议鼓件编码（0底鼓/1军鼓/2闭镲）
与 `voice_render` 的 voice 类型（1/2/3）**不是一套编号**，必须映射，
详见 `doc/protocol_v1_对接说明.md`。

**2. 底鼓扫频终止频率是 55Hz，不是任务书写的 40Hz**
已与队长确认保持 55Hz（黄金模型实测冲击感更好）。
若评审要求对齐任务书，改 `lib/init_engine.m` 里 `P.kick_f1 = 40` 重跑即可。

## 五、依赖他人（当前阻塞）

| 依赖项 | 负责人 | 用途 |
|---|---|---|
| 《演奏数据包协议 v1》 | 队员 A | B 的 `demo_song.m` 曲谱格式、C 的 `serial_player` |
| `piano_synth.m` 定稿 | 队员 A | 替换 demo 里的占位钢琴 |
| Gowin pROM `.mi` 格式确认 | 队员 C | 波形表烧录 |

## 六、一键复现

```matlab
cd sim/teamB/drum_sim_matlab
export_drum_deliverables     % 出三鼓件 wav + 图 + 参数表（约 10 秒）
main_drum_engine             % 出 32 声部黄金模型 + golden 向量（约 70 秒）
```
