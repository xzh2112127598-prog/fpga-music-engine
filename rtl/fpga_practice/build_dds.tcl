#============================================================
# Gowin 命令行一键编译：DDS 上板验证（Tang Primer 25K）
# 用法：双击同目录 build_dds.bat
# 产物：impl\pnr\demo_dds.fs
#============================================================

open_project demo_dds.gprj

# clk(E2)=CPU 专用脚、led[1](D7)=DONE、led[2](E8)=READY，必须开复用
set_option -use_cpu_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1

run all
exit
