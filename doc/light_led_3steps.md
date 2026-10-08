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

## 记住这一句

**点灯不是目的，是验证"写代码 → 编译 → 下载 → 板上跑"这条链路通了。**
链路通了之后，后面做的每一个模块都能立刻上板验证，不用再靠猜。
