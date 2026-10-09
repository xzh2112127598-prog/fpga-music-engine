# 点灯 · 操作卡（只写动作，原理见 gowin_bringup.md）

> 全程约 3 分钟。遇到任何一步报错，直接翻到最下面的"卡住了"。

---

## 第 0 步 · 接线

- USB-C 线插板子，另一头插电脑。
- **不需要外接下载器**，板载就有调试器。
- 板子上的灯如果亮了，说明供电正常。

---

## 第 1 步 · 打开工程

双击这个文件：

```
D:\GitHub\fpga-music-engine\rtl\fpga_practice\led_top.gprj
```

打开后看左下角/标题栏，确认显示的是 **GW5A-25**。
如果弹出"器件不匹配"之类，说明打开方式不对，用 Gowin EDA 菜单
`File → Open Project` 再选一次这个文件。

---

## 第 2 步 · 编译（二选一）

### 甲种 · 双击脚本（推荐，不会报错）

双击：

```
D:\GitHub\fpga-music-engine\rtl\fpga_practice\build_led.bat
```

黑窗口跑完，最后出现 `Build finished. Bitstream: impl\pnr\led_top.fs` 就成了。
**直接跳到第 3 步。**

### 乙种 · 在 Gowin 里点

点工具栏的**双箭头图标**（Run All，跑全流程）。

如果底部红字出现：

```
ERROR (PR2017) ... dedicated pin (CPU/SSPI)
ERROR (PR2017) ... dedicated pin (DONE)
ERROR (PR2017) ... dedicated pin (READY)
```

去这里勾三个开关：
`Project`（工程）→ `Configuration`（配置）→ 左边 `Place & Route`（布局布线）
→ 右边认准 **CPU / DONE / READY** 三个词，全勾上 → OK → 再点一次 Run All。

> 界面是中文还是英文无所谓，认准这三个英文词即可。

---

## 第 3 步 · 下载

1. Gowin EDA 菜单 `Tools` → `Programmer`（也可以开始菜单单独打开 Gowin Programmer）
2. 点 **Scan Device**（扫描设备）—— 能读出 GW5A 就说明连上了
3. 双击 `File Name` 那一行 → 选 `D:\GitHub\fpga-music-engine\rtl\fpga_practice\impl\pnr\led_top.fs`
4. **Operation 选 `SRAM Program`**（下载到 SRAM，掉电消失，调试阶段用这个，最快最安全）
5. 点 **Program / 下载**

底部出现 `Program Success` 或进度条走满即成功。

---

## 第 4 步 · 看现象（这一步就是过关）

| 灯 | 应该看到 |
|---|---|
| **led[0]**（L6） | 每秒闪一次 |
| **led[1]**（D7） | 呼吸灯，约 1 秒一个明暗循环 |
| **led[2]**（E8） | 按一次 K6 键翻转一次（按一下亮，再按一下灭） |

三个都对 = 工具链打通。

---

## 卡住了

| 现象 | 怎么办 |
|---|---|
| `PR2017 / PR2028 dedicated pin` | 第 2 步乙种的三个开关没勾。嫌麻烦就用甲种脚本 |
| Programmer 扫不到芯片 | 换 USB 口、换线；设备管理器看有没有"未知设备" |
| 下载时报 IDCODE 不匹配 | 器件 Version 从 **A** 改成 **B**，重新编译再下 |
| 三个灯全不亮 | 先确认下载报了成功；再确认用的是 `tang_primer_25k.cst` |
| 只有 led[0] 闪，按键没反应 | 按键极性：`led_top.v` 里 `wire key_high = ~key;` 改成 `= key;` 试试 |
| `.bat` 双击一闪而过 | 用命令行跑：`cd` 到该目录，执行 `build_led.bat` 看报错 |

---

## 下一步 · DDS 上板验证（点灯过了再做）

这一步要验证一件**决定整个方案成败**的事：你的芯片（Version A）没有分布式 RAM，
正弦波表只能放进块 RAM（BSRAM）。如果放不进去，整个合成引擎都要换方案。

### 操作

1. 双击编译：`D:\GitHub\fpga-music-engine\rtl\fpga_practice\build_dds.bat`
2. Programmer 下载 `impl\pnr\demo_dds.fs`（还是选 **A/1** 通道、SRAM Program）
3. 看现象（**每个灯对应一个独立结论**，一个一个看）：

| 灯 | 应该看到 | 它回答的问题 |
|---|---|---|
| **led[0]**（L6） | **精确 1Hz 闪烁**（1 秒亮 1 秒灭）；每按一次键变快一档 1→2→3→4Hz | 正弦表真的进了 BSRAM 吗？DDS 频率准吗？ |
| **led[1]**（D7） | **按住 S1 或 S2，这个灯立刻变化**，松开回原状 | 按键到底接在哪个脚？（这个灯接的是按键原始电平，最灵敏） |
| **led[2]**（E8） | **每按一次键翻转一次，并保持** | 消抖对不对？（手抖 10 次也只翻 1 次） |

**用手机秒表对一下 led[0]：应该 1 秒亮 1 秒灭。** 差得不多就是对的。

> 这个现象比呼吸灯难造假——如果 ROM 没初始化，led[0] 会**完全不亮或常亮**，
> 只有 DDS 真的在算、ROM 真的存了正弦表，它才会按精确频率闪。
> 闪烁频率能跟着按键一档一档变快，说明频率字（FTW）是真的在控制相位累加器。

### 已经替你验证过的（2026-10-09 编译记录）

```
BSRAM: 2/56 块占用（正弦表成功进块 RAM）✅
SSRAM(分布式RAM): 0 ✅（Version A 没有，符合预期）
时序：建立时间余量 +9.690 ns ✅
引脚：K6 / H11 / L6 / D7 / E8 全部落位 ✅
码流：impl/pnr/demo_dds.fs 生成成功（6.07 MB）✅
```

### 怎么用图形界面编译（不想用黑框的话）

黑框脚本只是把步骤自动化，**你可以在 Gowin 界面里做，完全一样**：

1. `File` → `Open Project` → 选你要编的那个 `.gprj`
   （`led_top.gprj` = 点灯，`demo_dds.gprj` = DDS 验证，两个是**独立工程**）
2. 点工具栏的**双箭头图标 Run All**
3. **如果报 `PR2017 / PR2028 dedicated pin`**：
   `Project` → `Configuration` → 左边 `Place & Route` → 认准 **CPU / DONE / READY**
   三个词全勾上 → OK → 再点 Run All
4. 产物在 `impl\pnr\*.fs`，拿去 Programmer 下载

> **记住：一次只能跑一个程序。** 每个 `.gprj` 编出自己的 `.fs`，下载新的会覆盖旧的。
> Programmer 里 `File Name` 那行要指向你刚编出来的那个 `.fs`。

## 按键怎么找

`K6`、`H11`、`L6` 这些是 **FPGA 芯片的 BGA 焊球编号**，板子丝印不会印。
板上接 FPGA 的按键只有 **2 个**（第 3 个多半是调试器的 BOOT 键，按了没反应）。
代码里已经把两个按键并联，**按任意一个都有反应**，挨个试就行。

---

## 下一步 · MPU6050（GY-521）上板验证

### 接线（Dock 上边缘最左的 PMOD = J6）

| GY-521 | J6 引脚 | FPGA 球号 |
|---|---|---|
| VCC | pin1 或 pin2（3V3） | - |
| GND | pin3 或 pin4 | - |
| SCL | **pin12** | G5 |
| SDA | **pin11** | F5 |

XDA / XCL / AD0 / INT **全部不接**。
模块板上自带 2.2k 上拉和 AD0 下拉，不用外加电阻，地址就是 0x68。
**VCC 和 GND 不能接反**，会烧模块；SCL/SDA 接反只是不通，换过来就行。

### 操作

1. 双击编译：`D:\GitHub\fpga-music-engine\rtl\fpga_practice\build_mpu.bat`
2. Programmer 下载 `impl\pnr\demo_mpu.fs`（SRAM Program）
3. 看现象：

| 灯 | 现象 | 含义 |
|---|---|---|
| **led[0] = D7**（板子丝印 **LED4**）**重点** | **常亮** | 一切正常：静止时合加速度 ≈ 1g（读数落在 1500~3800 LSB） |
| | 1Hz 慢闪 | I2C 起来了但读数不对（读到全 0 或全 1，多半是电源/线序问题） |
| | 8Hz 快闪 | 出现过 ACK 错误（接线断了 / 没供电 / 地址不对） |
| | 全灭 | 还在上电初始化的 100ms 内 |
| **led[1] = E8**（板子丝印 **LED3**） | 敲一下桌子闪 150ms | 加速度真的在变，链路全通 |
| | 按住 S2 转模块，灯跟着翻 | X 轴单轴数据在变（确认哪个轴对应哪个方向） |

按住 S1 可以把敲击阈值降到 1/4（更灵敏）。

> **板上能点的用户灯只有这 2 颗**（官方原理图已核实）：丝印 LED4 = FPGA 球 D7，
> 丝印 LED3 = FPGA 球 E8。另外那两颗灯是**电源灯**（接 3V3，通电常亮），FPGA 控制不了。
> 旧版文档里说的"L6 是第 3 颗灯"是错的 —— L6 是 USB-A 口的 D+ 数据线，那个"灯"从来不会亮。

### 已经替你验证过的（2026-10-09 编译记录）

```
引脚：led[0]=D7(LED4)  led[1]=E8(LED3)  scl=G5  sda=F5(双向 io)
      clk=E2  key=K6  key2=H11
资源：LUT 786/23040 (4%)   Register 420/23280 (2%)   BSRAM 0   SSRAM 0
时序：无违例
码流：impl/pnr/demo_mpu.fs 生成成功（5.96 MB）
约束文件：demo_mpu.cst（专用，不共用 tang_primer_25k.cst，因为那个文件里 led[0]=L6 有误）
```

---

## 记住这一句

**点灯不是目的，是验证"写代码 → 编译 → 下载 → 板上跑"这条链路通了。**
链路通了之后，后面做的每一个模块都能立刻上板验证，不用再靠猜。
