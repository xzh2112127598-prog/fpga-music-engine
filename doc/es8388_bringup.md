# ES8388 声卡上板指南（demo_es8388）

> 目标：耳机里听到 FPGA 自己合成的 440Hz 正弦音，打通
> 「纯硬件合成 → 数字音频 → ES8388 → 耳机」整条链路。
> 这是队员 B 三鼓件出声的前置必经步骤。

## 1. 为什么是 ES8388 而不是"DAC"

ES8388 是**编解码器（codec）**，不是纯 DAC：上电不会自己出声，
必须先用 I2C 写约 24 个寄存器（打开电源、配 I2S 格式、配音量），
然后 FPGA 再通过 I2S 串行口送样本才有声音。

好消息：它和我们 MPU6050 用**同一种 I2C 总线**，地址 0x10（MPU6050 是
0x68），可以共用一根总线；I2C 配置阶段**不需要 MCLK 也能工作**。

参考代码来自指导老师给的 `voice_changer_phone`（安路 EG4S20 工程），
6 个 Verilog 文件是纯通用逻辑，已原样移植到本仓库 `rtl/es8388/`，
只重写了时钟部分（安路的 EG_PHY_PLL → 高云 GW5A 的 PLLA 原语）。

## 2. 模块排针定义（已从原理图核实）

模块板上是 **J0：TSW-112-07-G-D，2×12 排针（24 脚）**，
丝印 **1 = 方形焊盘**。原理图截图见
`doc/img/es8388_module_header.png`（来自《ES8388声卡原理图.pdf》）。

| 排针脚 | 网络名 | 方向（相对 FPGA） | 接到 Tang Primer 25K Dock J6 |
|-------:|--------|:---:|------------------------------|
| 23 | 3.3V | — | J6 pin1 或 pin2（3V3） |
| 24 或 21 | GND | — | J6 pin3 或 pin4（GND） |
| 14 | I2C_SCL | → | J6 pin12（FPGA 球 G5） |
| 16 | I2C_SDA | ↔ | J6 pin11（FPGA 球 F5） |
| 12 | I2S_MCLK | → | J6 pin5（FPGA 球 H5） |
| 10 | I2S_SCLK | ← | J6 pin6（FPGA 球 J5） |
| 6 | I2S_LRCK | ← | J6 pin7（FPGA 球 H8） |
| 8 | I2S_SDIN | → | J6 pin8（FPGA 球 H7） |
| 4 | I2S_SDOUT | ← | J6 pin9（FPGA 球 G7） |
| 其余（1/2/5/…/20/22 等奇数脚） | 悬空 | — | 不接 |

共 9 根杜邦线（电源 2 + 地 1 + 信号 6）。
**注意 SCLK/LRCK/SDOUT 的箭头方向：ES8388 被配置成主机（R8=0x80），
BCLK 和 LRCK 是芯片产生后送回 FPGA 的，别接反。**

- 模块 I2C 已板载 2.00kΩ 上拉（R17/R18），每个信号线上还有 10Ω 串阻。
- 模块上**红色 LED 是电源灯**，通电常亮 = 供电 OK，先看它。
- 模块插座：J1 耳机（3.5mm）、J2 LINE IN、J3 麦克风、PH2.0-2P 喇叭。
  本 demo 只用 **J1 耳机**。

## 3. 时钟方案（GW5A 专属坑）

GW5A(Arora-V) 的 PLL 原语和 GW1N/GW2A **不同名**：

| 尝试 | 结果 |
|------|------|
| `rPLL`（GW1N/GW2A 用法） | EX3937 unknown module |
| `PLL`（UG306 文档里的原语名） | RP0008 no PLL resource |
| **`PLLA`** | ✅ 综合通过 |

PLLA 频率公式：`Fout = CLKIN/IDIV × FBDIV × MDIV / ODIV0`，
且 **PFD 必须在 19~87.5MHz**、**VCO 700~1400MHz**。

本配置：`50MHz ÷1 ×1 ×14.5 ÷59 = 12.288136MHz`（+11.0ppm，与参考
工程的安路板同解；fs = 48000.53Hz）。MDIV 支持 1/8 小数（14.5 =
14 + 4/8）。曾找到精确 12.288MHz 的解（÷5×6×16÷78.125），但
PFD=10MHz 低于下限，被拒。

DDS 频率字按真实 fs 算：`FTW = round(f × 2^32 / 48000.53)`。

## 4. 编译与下载

```bash
cd rtl/fpga_practice
build_es8388.bat          # 或 gw_sh < build_es8388.tcl
# 产物 impl/pnr/demo_es8388.fs
```

Gowin Programmer 里 **SRAM 下载** demo_es8388.fs（断电即失，反复改没关系）。

## 5. 现象与诊断

| 灯 | 含义 |
|----|------|
| POWER（LED1/LED5） | 电源，常亮 |
| **LED4（D7）** | PLL 锁定，常亮 = MCLK 正常 |
| **LED3（E8）** | 配置中 1Hz 慢闪；**常亮 = 24 个寄存器写完** |

耳机听感：440Hz 正弦音（约 1/4 满度，不炸耳）。
按 **S1（K6）** 循环换挡：440Hz → 1000Hz → 261.6Hz(C4) → 静音。

**排障顺序**（E8 常亮但没声音时）：
1. 模块红色电源灯亮不亮？不亮 = 3.3V/GND 没接好（查 J6 pin1/2/3/4）。
2. 耳机插的是 **J1**？音量开没开？（有的耳机阻抗高，正弦音本来就轻）
3. 都正常还没声：I2C 是否真写成功——demo 未检查 ACK，可把 SDA/SCL
   线临时对调试试（本工程不检查应答，接反了灯也全正常）。
4. 还不行：把现象发给队友，用 Gowin 在线逻辑分析仪抓 SDA/SCL。

## 6. 文件清单

| 文件 | 说明 |
|------|------|
| `rtl/es8388/es8388_audio_pll.v` | 【新写】GW5A PLLA：50M→12.288136MHz MCLK |
| `rtl/es8388/i2c_dri.v` | 移植。250kHz I2C 主机 |
| `rtl/es8388/i2c_reg_cfg.v` | 移植。24 寄存器配置表（R8=0x80 主机模式） |
| `rtl/es8388/es8388_config.v` | 移植+小改。把 cfg_done 引出点灯 |
| `rtl/es8388/es8388_ctrl.v` | 移植+小改。同上 |
| `rtl/es8388/audio_receive.v` | 移植。I2S 接收（本 demo 未用，留作变声/录音） |
| `rtl/es8388/audio_send_mono.v` | 移植。I2S 发送，单声道复制到左右 |
| `rtl/fpga_practice/demo_es8388.v` | 【新写】顶层：DDS 440Hz 音源 |
| `rtl/fpga_practice/demo_es8388.cst` | 【新写】J6 引脚约束 |
| `rtl/constraints/demo_es8388.sdc` | 【新写】双时钟域约束 |
| `rtl/fpga_practice/build_es8388.tcl/.bat` | 一键编译 |

## 7. 下一步

1. **鼓机上耳机**：把 `demo_es8388.v` 里的 osc_dds 换成敲击事件触发的
   三鼓件合成（hit_detector + 队员 B 的鼓引擎），评委戴耳机听。
2. **PC 端展示**：板载 UART（B3/C3，经 BL616 到 USB 虚拟串口）把波形
   数据传电脑画图，作为第二演示通道。
3. 积分整个引擎时，ES8388 侧逻辑（`rtl/es8388/`）原样复用，
   只需把 `dac_data` 接到引擎混音输出。
