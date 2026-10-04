# 芯上乐府 · 鼓组算法黄金模型（MATLAB · P2）

FPGA 实时多音色合成电子乐器引擎的**定点黄金模型**。硬件未到期间，用 MATLAB 把算法、
32bit 定点位宽、32 声部、真实音色、混响、延迟、可视化全部验证到"移植就绪"，
RTL 直接照着 `lib/` 逐模块直译。

## 怎么运行

在本目录打开 MATLAB：

- `main_drum_engine` —— 主脚本，F5 一键全流程（32 声部黄金模型 + 黄金向量 + 验证报告）
- `export_drum_deliverables` —— 10.5 交付物导出（三鼓件 wav + 时域/频谱图 + 参数表）

无需任何工具箱（滤波/包络/混响全是纯数学实现）。运行后自动刷新下方各目录。

> ⚠️ **参数只改一处**：所有定点参数集中在 `lib/init_engine.m`。
> 改完重跑上面任一脚本，参数表与 ROM 会自动重新生成。
> （历史教训：`drum_params.md` 曾手写成 24bit，与 RTL 的 32bit 漂移。）

## 目录结构

```
drum_sim_matlab/
├── main_drum_engine.m   ← 【主脚本】32 声部黄金模型全流程
├── export_drum_deliverables.m ← 【10.5 交付】三鼓件 wav + 图 + drum_params.md
├── lib/                 ← 21 个硬件对齐函数（RTL 就照这个写）
│   ├── ★参数源：init_engine        【唯一参数真源】改参数只改这里
│   ├── 数据通路：dds_render / dds_render_ip / lut_ip / q15mul / sat16 / mix_tree
│   ├── 振荡器：  make_sine_table / make_noise_table / ftw_calc / export_mi / midi_name
│   ├── 声部：    voice_init / voice_noteon / voice_noteoff / voice_render
│   │             adsr_step / vel_curve / piano_env
│   └── 效果器：  reverb_init / reverb_tick
├── params/              ← 生成的参数 / ROM（要烧进 FPGA 的东西）
│   ├── sine_1024.mi      正弦波表 1024×16bit
│   ├── noise_8192.mi     LFSR 噪声表 8192×16bit
│   ├── kick_sweep.mi     底鼓扫频 256×32bit【频率字 FTW，不是 PCM】
│   ├── note_freq.md      MIDI 0-127 频率 + 32bit 频率字全表
│   └── drum_params.md    寄存器映射参数文档
├── audio/               ← 输出：fpga_demo_mix.wav（含混响合奏试听）
├── fig/                 ← 输出：3 张图
│   ├── fpga_demo_mix.png   系统波形
│   ├── spectrum.png        输出频谱（谐波结构）
│   └── lissajous.png       李萨如（音程可视化）
├── golden/              ← 6 组整数黄金向量（Verilog testbench 逐拍比对）
│   ├── dds_440_out / dds_440_ip_out   DDS 输出（无插值/插值）
│   ├── noise_out                      LFSR 噪声输出
│   ├── vel_curve                      力度曲线
│   └── imu_events / imu_az            IMU 检测事件与 az 波形
├── analysis/            ← 【真实样本分析，不进 FPGA】
│   ├── samples/drum/      15 个真实鼓样本（Dirt-Samples，含底鼓/军鼓/开闭锁镲）
│   ├── samples/piano/     6 个真实钢琴单音（C4/D4/E4/G4/C5/A2）
│   ├── analyze_samples.m  提取鼓频响峰值/衰减tau/频带能量
│   ├── analyze_piano.m    提取钢琴3谐波幅度比/衰减tau/起音
│   └── extracted_params.md / piano_extracted.md  提取结果
├── docs/
│   └── verify_report.txt              最终验证报告（指标全在这）
└── legacy/              ← 【归档】早期探索版本，不参与运行，仅供追溯
    ├── 01_explore/       9.28 第一版：double + randn 全链路探索
    ├── 02_floating/      10.4 第二版：double 三鼓合成/合奏/参数导出 + 调试脚本
    └── old_outputs/      早期 wav 与 7 张图
```

## 主脚本流程（7 步）

1. **Part 0**：生成正弦表 + LFSR 噪声表，导出 `.mi`；MIDI 频率字表；参数文档；
2. **Part 1**：模块自测（DDS 对齐 double、噪声 RMS、力度曲线）→ 黄金向量；
3. **Part 2**：32 声部分配器压力测试（400 随机事件）；
4. **Part 3**：系统级仿真——定点 IMU 检测 → 32 声部逐样本渲染 → 饱和混音；
5. **Part 4**：Freeverb 混响逐样本后处理（干湿混合）；
6. **Part 5**：延迟统计；
7. **Part 6/7**：李萨如、频谱、系统波形出图，写报告。

## P2 真实感增强要点

- **钢琴**：每 voice 3 个谐波振荡器（幅度比 1:0.35:0.12），各自独立包络
  （起音 10ms，按住衰减 tau 1.2/0.6/0.3s，松键快速释放）；
- **底鼓**：扫频 150→55Hz，加入鼓槌击皮的攻击 click（10ms 高频瞬态）；
- **军鼓**：响弦噪声带通提高到 5–9kHz（真实响弦频段，更亮）；
- **镲**：噪声带通 7–10kHz + 3 个非谐金属共振正弦（6200/7900/9400Hz）；
- **混响**：4 并行 comb + 2 串联 allpass（Freeverb），营造空间感。

## 最终验证指标（docs/verify_report.txt）

| 指标 | 结果 | 要求 |
|---|---|---|
| 削波样本 | 0 | 无爆音 |
| 输出峰值 | 31285 | 电平充足 |
| 端到端延迟 | 平均 6.00 / 最大 6.02 ms | ≤10 ms |
| 声部调度 | 峰值并发 32、窃取 238 | 复音 |
| 插值 DDS 误差 | 2 LSB（32bit 频率字） | 听感无影响 |
| LFSR 噪声 RMS | 18819（理论 18919） | — |

## 合规红线（务必遵守）

- 鼓/钢琴的**FPGA 音源全部数学合成**（正弦扫频 + 噪声 + 包络 + 效果器），无预录 PCM；
- `analysis/samples/` 下的真实录音**仅用于离线分析、提取谐波/包络参数**，不进入 FPGA；
- `kick_sweep.mi` 存的是**频率控制字（参数）**，不是 PCM，属合法查表；
- 导出的 `audio/*.wav` 仅供试听和算法验证，**不能直接存进 FPGA 播放**。

## 待对接

- 队员 A 的 `piano_synth.m` 定稿后，替换主脚本临时钢琴排程（3 谐波框架可直接沿用）；
- 队员 C 取 `params/kick_sweep.mi`、`note_freq.md`、`drum_params.md` 做硬件寄存器；
- 硬件到手后，testbench 读 `golden/` 逐拍验证，对比 MATLAB 与 FPGA 输出。
