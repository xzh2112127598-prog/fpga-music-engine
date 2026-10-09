@echo off
REM ============================================================
REM  Gowin one-click build for the MPU6050 on-board demo
REM  Output: impl\pnr\demo_mpu.fs
REM ============================================================
set GW_SH=D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe

if not exist "%GW_SH%" (
  echo [ERROR] Cannot find gw_sh.exe
  echo         Please edit GW_SH path in this .bat file.
  pause
  exit /b 1
)

cd /d "%~dp0"
"%GW_SH%" < build_mpu.tcl
echo.
echo ---- Build finished. Bitstream: impl\pnr\demo_mpu.fs ----
pause
