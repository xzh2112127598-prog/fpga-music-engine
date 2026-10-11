@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==== 编译 demo_drum（电子鼓：MPU6050 + ES8388）====
"D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe" < build_drum.tcl
echo.
echo ==== 产物 ====
if exist impl\pnr\demo_drum.fs (
    echo impl\pnr\demo_drum.fs
) else (
    echo 编译失败，请看上面的报错
)
pause
