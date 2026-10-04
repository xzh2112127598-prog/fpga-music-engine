# 芯上乐府 · 仓库说明

全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 创新设计赛道（高云半导体）
选题二「基于 FPGA 的实时多音色合成电子乐器引擎」
板卡：Sipeed Tang Nano 20K（GW2AR-LV18，27MHz 晶振）

## 目录

```
fpga-music-engine/
├── sim/
│   ├── teamA/            队员 A：钢琴 MATLAB 仿真 + LUT 生成
│   └── teamB/            队员 B：鼓组 MATLAB 仿真 + 定点黄金模型
│       └── drum_sim_matlab/
├── rtl/                  Verilog（fpga_practice = 入门练习 01-04）
├── doc/                  全队交付文档（参数表、协议）
└── tools/                格式转换等脚本
```

## 全队统一口径（队长 2026-10-04，任何人不许偏离）

| 项 | 值 |
|---|---|
| 采样率 | **48000 Hz** |
| 样本 | **int16（Q15）** |
| 频率字 | **`freq_word = round(f × 2^32 / 48000)`** ← 32bit |
| 钢琴每 voice | 3 个独立振荡器，幅度比 `1 : 0.35 : 0.12` |
| 包络时间常数 | 基频 1.2 s、2 次 0.6 s、3 次 0.3 s，起音 10 ms |
| MIDI 频率表 | `sim/teamB/drum_sim_matlab/params/note_freq.md` |

> ⚠️ 历史上 `drum_params.md` 曾写成 24bit（150Hz → FTW 52429），已修正为
> 32bit（150Hz → FTW 13421773）。**任何参数表都由代码生成，不要手改。**

## 参数单一真源

所有定点参数集中在 `sim/teamB/drum_sim_matlab/lib/init_engine.m`。
改参数只改这一个文件，然后重跑：

```matlab
cd sim/teamB/drum_sim_matlab
export_drum_deliverables     % 出三鼓件 wav + 图 + params/drum_params.md
main_drum_engine             % 出 32 声部黄金模型 + golden 向量 + 验证报告
```

## 合规红线

- 全程纯硬件合成，**工程内不存在任何预录 PCM 音源**；
- `*.wav` 与 `analysis/samples/` 已在 `.gitignore` 中排除，不入库；
- `analysis/samples/` 里的真实鼓/钢琴录音**只用于离线标定**（提取衰减时间、
  频段能量），不参与任何音频输出，结论见 `analysis/extracted_params.md`；
- `kick_sweep.mi` 存的是**频率控制字（参数）**，不是 PCM 波形，属合法查表。
