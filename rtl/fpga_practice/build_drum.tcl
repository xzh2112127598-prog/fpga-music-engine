#============================================================
# Gowin 命令行一键编译：电子鼓 demo_drum（Tang Primer 25K）
# 用法：双击同目录 build_drum.bat
# 产物：impl\pnr\demo_drum.fs
#============================================================

open_project demo_drum.gprj

# clk(E2)=CPU、led[0](D7)=DONE、led[1](E8)=READY，必须开复用
set_option -use_cpu_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1

run all
exit
