# 环境搭建（队员 B / 队员 C 共用）

## 一、已完成

| 软件 | 版本 | 位置 | 状态 |
|---|---|---|---|
| Gowin EDA | V1.9.11.03 Education | `D:\Gowin\Gowin_V1.9.11.03_Education_x64` | ✅ 已装 |
| MATLAB | R2025a | `D:\Program Files\MATLAB\R2025a` | ✅ 已装 |
| **Verilog 仿真器** | — | — | ❌ **缺失，当前阻塞项** |

> ⚠️ Gowin EDA **本身不带仿真器**。它的 `Tools → Simulation` 需要关联外部
> ModelSim/Questa。当前机器上 ModelSim、iverilog、verilator 均未安装，
> 所以现在写出来的 RTL 无法验证。这是第一步要解决的。

## 二、安装 Questa-Intel FPGA Starter Edition（免费）

Intel 已用 **Questa-Intel FPGA Edition** 取代 ModelSim-Intel FPGA Edition
（自 Quartus 21.1 起）。Starter Edition 免费，只是速度受限，对我们够用。

### 1. 下载（不需要装 Quartus）

1. 打开 Intel FPGA Software Download Center
   `https://www.intel.com/content/www/us/en/software-kit/667301/`
   （若链接变动：Intel 官网 → FPGA → Downloads → 筛选 Quartus Prime Lite Edition）
2. 切到 **Individual Files** 标签页
3. 找 **QuestaSetup** 的 Windows 版本下载（约 1–2 GB）

### 2. 安装

- 安装路径**必须全英文、无空格**，建议 `D:\FPGA_Tools\Questa`
  （EDA 工具对中文路径和空格支持很差，会报莫名其妙的错）
- 安装类型选 **Questa-Intel FPGA Starter Edition**（免费版）

### 3. 申请免费 License

1. 注册/登录 Intel 账号，进 Intel FPGA Self-Service Licensing Center
2. 选 **Questa-Intel FPGA Starter Edition**，座位数填 1
3. New Computer → 填网卡 MAC 地址
   - 查 MAC：Win+R → `cmd` → `ipconfig /all` → 找 **Physical Address**，去掉横线
4. Generate License → 邮箱收到 `license.dat`

> 已知坑：部分用户反馈老 Intel 账号申请失败。遇到就清 Cookie /
> 换无痕窗口 / 换浏览器重试，或换个邮箱重新注册（有说法称需非免费邮箱）。

### 4. 配置环境变量

新增系统环境变量：

```
变量名：LM_LICENSE_FILE
变量值：D:\FPGA_Tools\licenses\license.dat   （改成你实际放置的路径）
```

设置完**需要注销重登或重启**才生效。

### 5. 关联到 Gowin EDA

Gowin EDA → `Tools` → 仿真设置 → 指向 Questa 的 `vsim.exe`。

## 三、Questa 与 ModelSim 的一个差异（会坑到你）

Questa 默认会在优化阶段**删掉未使用的信号**，ModelSim 不会。
testbench 里专门拉出来看波形的信号会被优化掉，波形窗口里找不到。

解决办法：`vsim` 时加参数

```
vsim -voptargs=+acc work.tb_xxx
```

## 四、验证 RTL 的跑法（装好后）

```bash
# 以敲击检测为例
cd rtl/tb
vlog ../src/isqrt.v ../src/hit_detector.v tb_hit_detector.v
vsim -voptargs=+acc work.tb_hit_detector
add wave -r *
run 20ms
```

`tb_hit_detector` 会自动读取 `golden/imu_az.hex` 作为激励，
并与 `golden/imu_expect.hex` 中的期望事件逐条比对，打印 PASS/FAIL。

## 五、备选：Icarus Verilog（装 Questa 期间可先用）

几十 MB，命令行跑，写 I2C/DDS/状态机 testbench 足够：

```bash
winget install IcarusVerilog.IcarusVerilog     # 或去 GitHub Release 下免安装 zip
iverilog -o sim.vvp ../src/isqrt.v ../src/hit_detector.v tb_hit_detector.v
vvp sim.vvp
gtkwave dump.vcd
```

不必二选一，两个可以共存。
