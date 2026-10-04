# RTL 进度与验证状态

> ⚠️ **`rtl/src/` 下所有模块目前均未经过仿真验证**——本机没有安装任何 Verilog
> 仿真器（ModelSim / iverilog 都没有）。装好仿真器后的第一件事就是跑 `rtl/tb/`。
> 安装步骤见 `doc/env_setup.md`。

## 已完成模块

| 文件 | 功能 | 对应 MATLAB | 验证状态 |
|---|---|---|---|
| `src/isqrt.v` | 整数平方根（16 迭代） | `sqrt()` | 待仿真 |
| `src/i2c_master.v` | I2C 主机，400kHz，7bit 地址，重复起始，突发 8 字节 | — | 待仿真 |
| `src/mpu6050_reader.v` | MPU6050 初始化 + 循环读三轴 | — | 待仿真 |
| `src/hit_detector.v` | 敲击检测状态机 | `main_drum_engine` Part 3 | 待仿真（黄金向量已就绪） |

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

- [ ] 装仿真器（见 `doc/env_setup.md`）
- [ ] 跑 `tb_i2c_master`，核对 SCL/SDA 时序与 ACK
- [ ] 跑 `tb_hit_detector`，与 `golden/imu_expect.hex` 逐条比对
- [ ] `i2s_tx.v`（送 PCM5102，48kHz/16bit，BCLK=3.072MHz）
- [ ] `test_mode.v`（测试模式，现场硬指标，见 `doc/next_steps.md`）
- [ ] `key_scan.v`（12 键扫描 + 乐观消抖）
- [ ] 顶层集成 + 时序约束 `.cst`（Tang Nano 20K 晶振是 **27MHz**，不是 24MHz）
