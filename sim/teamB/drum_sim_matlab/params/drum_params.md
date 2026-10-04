# 鼓组合成参数表（FPGA 对齐版 · 32bit）

> 本文件由 `export_drum_deliverables.m` **自动生成**，请勿手改。
> 改参数请改 `lib/init_engine.m`，再重跑本脚本。

## 全局口径

| 项 | 值 |
|---|---|
| 采样率 | 48000 Hz |
| 样本 | int16（Q15） |
| 相位/频率字位宽 | 32 bit |
| 频率字公式 | freq_word = round(f x 2^32 / 48000) |
| 混音 | 32 路饱和加法树 + sat16 |

| 波表 | 深度 | 地址取相位 | 文件 |
|---|---|---|---|
| 正弦 | 1024 x 16bit | phase[31:22] | sine_1024.mi |
| 噪声 LFSR | 8192 x 16bit | phase[31:19] | noise_8192.mi |
| 底鼓扫频 | 256 x 32bit | 只读 FTW 非 PCM | kick_sweep.mi |

## 鼓件寄存器映射

| 参数 | 数值 | 频率字(32bit) | 位宽 | FPGA 寄存器 |
|---|---|---|---|---|
| kick 起始频率 | 150 Hz | 13421773 | 32bit | REG_KICK_F0 |
| kick 终止频率 | 55 Hz | 4921317 | 32bit | REG_KICK_F1 |
| kick 扫频时长 | 80 ms（3840 样本） | - | - | REG_KICK_TIME |
| kick 扫频表 | 256 点指数滑音 | 见 kick_sweep.mi | 32bit | ROM |
| kick click | 10 ms，低通 3000 Hz | - | - | REG_KICK_CLICK |
| snare 模态 1 | 180 Hz | 16106127 | 32bit | REG_SNARE_F1 |
| snare 模态 2 | 200 Hz | 17895697 | 32bit | REG_SNARE_F2 |
| snare 响弦带通 | 5000 ~ 9000 Hz | - | 16bit | REG_SNARE_BP |
| hihat 噪声带通 | 7000 ~ 10000 Hz | - | 16bit | REG_HIHAT_BP |
| hihat 金属共振 1 | 6200 Hz | 554766609 | 32bit | REG_HIHAT_R1 |
| hihat 金属共振 2 | 7900 Hz | 706880034 | 32bit | REG_HIHAT_R2 |
| hihat 金属共振 3 | 9400 Hz | 841097762 | 32bit | REG_HIHAT_R3 |
| 噪声表步进 | 每样本地址 +1 | 524288 | 32bit | REG_NOISE_FTW |
| LFO 颤音 | 5 Hz | 447392 | 32bit | REG_LFO_F |

## 鼓件 ADSR（Q15 步进）

| 鼓件 | attack_step | decay_k | sustain | release_k | 近似衰减 |
|---|---|---|---|---|---|
| kick | 341 | 11 | 0 | 11 | 2^-11 指数衰减 |
| snare | 341 | 11 | 0 | 11 | 2^-11 指数衰减 |
| hihat | 683 | 9 | 0 | 9 | 2^-9 指数衰减 |

## 钢琴（队长口径，供 A 对齐）

| 项 | 值 |
|---|---|
| 谐波数 | 3（独立相位累加器） |
| 幅度比 | 1 : 0.35 : 0.12 |
| 包络时间常数 | 1.2 / 0.6 / 0.3 s |
| 起音 | 10 ms |

## 可区分性验证（三频段能量占比）

| 鼓件 | 低频 0-200Hz | 中频 0.2-2kHz | 高频 2-24kHz | 峰值 | 削波 |
|---|---|---|---|---|---|
| kick | 1.00 | 0.00 | 0.00 | 15250 | 0 |
| snare | 0.52 | 0.10 | 0.37 | 10860 | 0 |
| hihat | 0.00 | 0.00 | 1.00 | 6468 | 0 |

判据：底鼓低频独占、镲高频独占、军鼓呈低频鼓膜 180/200Hz + 高频响弦 5~9kHz 双峰。三者频段重心互不相同，即可判定音色可区分"音色可区分"。

## 合规说明

- 三鼓件全部由正弦扫频 / LFSR 噪声 / 一阶滤波 / ADSR 现场合成，**无任何录音参与**；
- `kick_sweep.mi` 存的是**频率控制字（参数）**，不是 PCM 波形，属合法查表；
- `audio/*.wav` 仅供试听与算法验证，**不进入 FPGA、不入库**（见 .gitignore）。
