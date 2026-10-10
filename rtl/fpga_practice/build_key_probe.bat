@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==== 编译 key_probe（按键探测）====
"D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe" < build_key_probe.tcl
echo.
echo ==== 产物 ====
if exist impl\pnr\key_probe.fs (
    echo impl\pnr\key_probe.fs
) else (
    echo 编译失败，请看上面的报错
)
pause
