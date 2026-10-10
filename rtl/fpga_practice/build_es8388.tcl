#============================================================
# Gowin 命令行一键编译：ES8388 声卡验证（Tang Primer 25K）
# 用法：双击同目录 build_es8388.bat（或在 gw_sh 里 source）
# 产物：impl\pnr\demo_es8388.fs
#============================================================

open_project demo_es8388.gprj

# clk(E2)=CPU 专用脚、led[0](D7)=DONE、led[1](E8)=READY，必须开复用
set_option -use_cpu_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1

run all
exit
