@echo off
REM ============================================================
REM  Gowin one-click build for Tang Primer 25K LED demo
REM  Output: impl\pnr\led_top.fs   (use Gowin Programmer to download)
REM ============================================================
set GW_SH=D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe

if not exist "%GW_SH%" (
  echo [ERROR] Cannot find gw_sh.exe
  echo         Please edit GW_SH path in this .bat file.
  pause
  exit /b 1
)

cd /d "%~dp0"
"%GW_SH%" < build_led.tcl
echo.
echo ---- Build finished. Bitstream: impl\pnr\led_top.fs ----
pause
