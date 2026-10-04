# RTL 进度与验证状态

> 仿真器：**Icarus Verilog 12.0** 已装（`C:\Users\XuXia\iverilog`），
> 一键回归 `bash tools/run_iverilog.sh all`。装法与踩坑见 `doc/env_setup.md`。

## 已完成模块

| 文件 | 功能 | 对应 MATLAB | 验证状态 |
|---|---|---|---|
| `src/isqrt.v` | 整数平方根（16 迭代，纯移位+减法，不用 DSP） | `sqrt()` | ✅ 随 hit_detector 跑通 |
| `src/i2c_master.v` | I2C 主机，400kHz，7bit 地址，重复起始，突发 8 字节 | — | ✅ **8/8 PASS**（含错误地址负测试） |
| `src/hit_detector.v` | 敲击检测状态机 | `main_drum_engine` Part 3 | ✅ **8/8 事件、2800/2800 样本逐位一致** |
| `src/mpu6050_reader.v` | MPU6050 初始化 + 循环读三轴 | — | ❌ **未验证（无 testbench）** |

### 验证明细

- `tb_i2c_master`：真行为级 I2C 从机模型（不是假位计数器），
  4 个事务 + SCL 频率测量全部 PASS：写 `0x6B=0x00`、写 `0x1C=0x18`(±16g)、
  读 `0x3B`×6 = `112233445566`、错误地址 `0x69` → `ack_err=1`；
  实测 SCL 周期 252 系统钟 = **396.8 kHz**（≤400kHz 上限）。
- `tb_hit_detector`：8 个敲击的**索引 / 类型 / 力度**与 MATLAB 黄金向量完全一致
  （300/1/103、701/2/48、1101/3/32、1400/1/80、1701/2/40、2002/3/24、2200/1/92、2401/1/45）。
- `tb_hit_trace` + `tools/diff_trace.py`：逐样本内部状态（dx/dy/dz/magsq/基线/状态机）
  与参考模型 diff，**0 处不一致**。

## 关键设计点（答辩会被问）

**1. 为什么有了平方比较还要开方？**
阈值比较确实可以用幅值平方躲开开根号（`magsq > THR_SQ`），
但**力度必须是真实幅值**（`vel = 幅值/(10g)×127`），所以 `isqrt` 躲不掉。
`isqrt` 纯移位+减法，不用 DSP，16 个周期出结果——在 27MHz 下是 0.6µs，
相对 1ms 的采样间隔可以忽略。

**2. 一个滤波器办两件事**
```
base += (cur - base) >> 5
```
- 减掉它 → 动作分量（敲击检测用）
- 保留它 → 重力方向（朝向分区用）

**3. 不对加速度做两次积分求位置** —— 漂移会爆炸，这是惯性导航的通病。

**4. MPU6050 量程必须 ±16g**（`ACCEL_CONFIG = 0x18`）。
默认 ±2g 一敲就爆表、力度全丢。±16g 下 1g = 2048 LSB。

**5. 不应期不能省** —— 鼓槌弹跳会造成一敲触发三四次，听着像机关枪。
当前 100ms；若现场发现连击，改 `REFR_MS` 到 120~150。

## 待办

- [x] 装仿真器（Icarus Verilog 12.0，见 `doc/env_setup.md`）
- [x] 跑 `tb_i2c_master`，核对 SCL/SDA 时序与 ACK
- [x] 跑 `tb_hit_detector`，与 `golden/imu_expect.hex` 逐条比对
- [ ] 给 `mpu6050_reader.v` 补 testbench（唯一未验证的模块）
- [ ] `osc_dds.v` + 插值查表（对拍 `golden/dds_440_ip_out.txt`，插值版误差仅 2 LSB）
- [ ] `adsr.v` + `vel_curve`（对拍 `golden/vel_curve.txt`）
- [ ] 噪声波表读取（对拍 `golden/noise_out.txt`，RMS 18819）
- [ ] `i2s_tx.v`（送 PCM5102，48kHz/16bit，BCLK=3.072MHz）
- [ ] `test_mode.v`（测试模式，现场硬指标，见 `doc/next_steps.md`）
- [ ] `key_scan.v`（12 键扫描 + 乐观消抖）
- [ ] 32 路饱和加法树（混音总线 24bit）
- [ ] 顶层集成 + 时序约束 `.cst`（Tang Nano 20K 晶振是 **27MHz**，不是 24MHz）

## ⚠️ 写 testbench 的硬规矩

给 DUT 的握手信号（`sample_valid` / `start` / `done` 之类）**必须用非阻塞赋值**：

```verilog
sample_valid <= 1'b1;    // 正确
@(posedge clk);
sample_valid <= 1'b0;
```

用阻塞赋值会让 DUT 在同一个 posedge 上把信号采到，导致**一个样本被处理两遍**。
症状极具迷惑性：事件数对、多数索引也对，只有个别事件偏早、力度偏小，
看着像 RTL 时序 bug，实际是 testbench 竞争。详见 `doc/env_setup.md` 第六节。
