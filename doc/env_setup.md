# 环境搭建（队员 B / 队员 C 共用）

## 一、已完成

| 软件 | 版本 | 位置 | 状态 |
|---|---|---|---|
| Gowin EDA | V1.9.11.03 Education | `D:\Gowin\Gowin_V1.9.11.03_Education_x64` | ✅ 已装 |
| MATLAB | R2025a | `D:\Program Files\MATLAB\R2025a` | ✅ 已装 |
| **Icarus Verilog** | 12.0 (devel) | `C:\Users\XuXia\iverilog` | ✅ 已装，当前主力 |
| GTKWave | 随 Icarus 附带 | 同目录 | ✅ 已装 |
| Questa-Intel FPGA Starter | — | — | ⏸ 待装（需 Intel 账号 + license） |

> ⚠️ Gowin EDA **本身不带仿真器**，必须关联外部的 ModelSim/Questa。
> 当前已用 **Icarus Verilog** 打通全流程，`tools/run_iverilog.sh` 一键回归，
> 两个 testbench 全绿。Questa 不是阻塞项了，可以在拿到板子前后再补。

### Icarus 是怎么装上的（换机器时照抄）

`winget install Icarus.Verilog` 会失败（清单里的安装包 URL 已 404）。可用走法：

```bash
winget show --id Icarus.Verilog --exact     # 拿到真实下载地址
# https://bleyer.org/icarus/iverilog-v12-20220611-x64_setup.exe
# 用 innoextract 解包（不要直接静默安装，会什么都不装还返回 0）
innoextract iverilog-v12-20220611-x64_setup.exe
cp -r app/* C:/Users/XuXia/iverilog/
iverilog -V     # Icarus Verilog version 12.0 (devel)
```

## 二、一键回归（推荐每天跑）

```bash
bash tools/run_iverilog.sh all        # I2C + 敲击检测
bash tools/run_iverilog.sh i2c_master
bash tools/run_iverilog.sh hit_detector
bash tools/run_iverilog.sh trace      # 导出逐样本内部状态，供对拍
```

`hit_detector` 会读 `golden/imu_*.hex` 作激励，与 `golden/imu_expect.hex`
逐条比对，打印 PASS/FAIL。当前结果：**8/8 事件、2800/2800 样本逐位一致**。

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

### Icarus 的两个已知差异

1. `timescale 1ns/1ps` 下 `$time` 打印出来是 **ps**（不是 ns），
   2800001500000 是 2.8 s，不是 2800 s。
2. `%0s` 打印中文字符串常量会乱码（尾部补 NUL），
   testbench 里的检查项名一律用 ASCII。

## 六、⚠️ testbench 里的 sample_valid 必须用非阻塞赋值

这个坑排查了一整轮，写下来免得再踩。

**错误写法**（看起来毫无问题，实际会让 DUT 把每个样本处理两遍）：

```verilog
for (idx = 0; idx < N_SAMP; idx = idx + 1) begin
    sample_valid = 1'b1;                              // 阻塞赋值！
    @(posedge clk);
    sample_valid = 1'b0;
    repeat (CLK_PER_SAMP - 1) @(posedge clk);
end
```

原因：`repeat` 的**最后一个 posedge** 上，`initial` 块恢复执行后立刻把
`sample_valid` 拉高（同一个时间步内）。若 `initial` 先于 DUT 的 `always` 执行，
DUT 在**这一拍**就采到了 1，于是同一个样本被处理两次 —— 基线每样本更新两遍、
峰值窗只覆盖一半的真实样本。

**症状**（很有迷惑性，容易误判成 RTL 时序 bug）：
- 敲击检测偏早 6 个样本；
- 力度明显偏小（峰值窗没走完）；
- 事件数仍然是对的，而且其中一部分事件的索引完全正确 —— 所以看起来像"时序差一点"。

**正确写法**：

```verilog
sample_valid <= 1'b1;      // NBA：当拍 DUT 仍看到 0
@(posedge clk);
sample_valid <= 1'b0;
repeat (CLK_PER_SAMP - 1) @(posedge clk);
```

同理，想在 testbench 里用 `always @(posedge clk) if (sample_valid) $display(...)`
抓内部信号时也会踩到同一个竞争：探针可能一行都不打印。用 NBA 后即正常。

## 七、对拍工具链（RTL ↔ MATLAB 黄金模型）

拿到板子前，验证只能靠"定点黄金模型 vs RTL 逐拍一致"。已建好三件套：

```bash
# 1) 参考模型：Python 精确复现 MATLAB Part 3，输出逐样本 trace
python tools/ref_hit.py sim/teamB/drum_sim_matlab/golden 0 2799 | grep ^TR > /tmp/ref.txt

# 2) RTL trace
bash tools/run_iverilog.sh trace     # -> sim/teamB/drum_sim_matlab/golden/rtl_trace.txt

# 3) 逐字段 diff，定位第一次分叉
python tools/diff_trace.py sim/teamB/drum_sim_matlab/golden/rtl_trace.txt /tmp/ref.txt 5 1
```

`ref_hit.py` 的输出已验证与 MATLAB 的 8 个事件**逐位相同**，
所以日常对拍不用每次启动 MATLAB（启动一次要 30 s+）。
**改动 hit_detector 的算法时，三边（MATLAB / ref_hit.py / RTL）必须同步改。**
