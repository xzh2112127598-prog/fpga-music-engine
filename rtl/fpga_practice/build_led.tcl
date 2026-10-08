#============================================================
# Gowin 命令行一键编译：Tang Primer 25K 点灯工程
#   这是 Gowin 自带的命令行外壳（gw_sh），不是第三方工具，符合赛规。
#   用法：双击同目录的 build_led.bat
#   产物：impl\pnr\led_top.fs  （拿这个文件去 Gowin Programmer 下载）
#============================================================

open_project led_top.gprj

# Tang Primer 25K 上，clk(E2) 是 CPU 专用脚、led[1](D7) 是 DONE、led[2](E8) 是 READY。
# 不开这三个开关，布局布线会报 PR2017/PR2028 "dedicated pin"。
set_option -use_cpu_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1

run all
exit
