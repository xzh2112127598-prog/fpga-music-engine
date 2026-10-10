#============================================================
# Gowin 命令行一键编译：按键探测（Tang Primer 25K）
# 用法：双击同目录 build_key_probe.bat
# 产物：impl\pnr\key_probe.fs
#============================================================

open_project key_probe.gprj

# led[0](D7)=DONE、led[1](E8)=READY，必须开复用
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1

run all
exit
