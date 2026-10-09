#!/usr/bin/env bash
# run_iverilog.sh —— 用 Icarus Verilog 跑本仓库的 Verilog 仿真
#
# 用法：
#   ./tools/run_iverilog.sh i2c_master        # I2C 主机 + 从机模型
#   ./tools/run_iverilog.sh hit_detector      # 敲击检测 vs MATLAB 黄金模型
#   ./tools/run_iverilog.sh osc_dds           # DDS（插值/查表/噪声）vs 黄金向量
#   ./tools/run_iverilog.sh trace             # 导出逐样本内部状态，供 diff_trace.py 对拍
#   ./tools/run_iverilog.sh rom               # 重新生成 golden/*.hex 波表并自校验
#   ./tools/run_iverilog.sh all
#
# Icarus 安装位置由 IVL 环境变量指定，默认 C:/Users/XuXia/iverilog/bin
# 注意：tb_hit_detector 里的 $readmemh 用的是相对路径 golden/，
#       所以必须在 golden/ 所在目录下启动 vvp。

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
IVL="${IVL:-C:/Users/XuXia/iverilog/bin}"
PY="${PY:-C:/Users/XuXia/.workbuddy/binaries/python/versions/3.13.12/python.exe}"
OUT="${REPO}/rtl/tb/sim_out"
GOLDEN_DIR="${REPO}/sim/teamB/drum_sim_matlab"

mkdir -p "$OUT"

compile() {   # $1=输出名  $2..=源文件（相对 REPO）
    local name="$1"; shift
    local files=()
    for f in "$@"; do files+=("${REPO}/${f}"); done
    echo "--- 编译 ${name} ---"
    "${IVL}/iverilog.exe" -g2012 -Wall -o "${OUT}/${name}.vvp" "${files[@]}" || return 1
}

run() {       # $1=输出名  $2=工作目录
    local name="$1"; local wd="$2"
    echo "--- 运行 ${name} ---"
    ( cd "$wd" && "${IVL}/vvp.exe" "${OUT}/${name}.vvp" ) || return 1
}

case "${1:-all}" in
  i2c_master)
      compile i2c_master rtl/src/i2c_master.v rtl/tb/tb_i2c_master.v &&
      run i2c_master "${REPO}/rtl/tb"
      ;;
  hit_detector)
      compile hit_detector rtl/src/isqrt.v rtl/src/hit_detector.v rtl/tb/tb_hit_detector.v &&
      run hit_detector "${GOLDEN_DIR}"
      ;;
  mpu6050)
      # MPU6050 初始化 + 三轴读取（含 ACCEL_CONFIG=0x18 量程校验与实测采样率）
      compile mpu6050 rtl/src/i2c_master.v rtl/src/mpu6050_reader.v rtl/tb/tb_mpu6050_reader.v &&
      run mpu6050 "${REPO}/rtl/tb"
      ;;
  osc_dds)
      compile osc_dds rtl/src/osc_dds.v rtl/tb/tb_osc_dds.v &&
      run osc_dds "${GOLDEN_DIR}"
      ;;
  rom)
      # 重新生成 golden/sine_1024.hex / noise_8192.hex，并跑定点 DDS 与黄金向量自校验
      "${PY}" "${REPO}/tools/make_rom_hex.py"
      ;;
  trace)
      # 逐样本 trace：输出 TR ... 行，与 tools/ref_hit.py 的参考 trace 逐行 diff
      compile trace rtl/src/isqrt.v rtl/src/hit_detector.v rtl/tb/tb_hit_trace.v &&
      run trace "${GOLDEN_DIR}" > "${GOLDEN_DIR}/golden/rtl_trace.txt"
      echo "trace 已写入 ${GOLDEN_DIR}/golden/rtl_trace.txt"
      echo "对拍：python tools/ref_hit.py sim/teamB/drum_sim_matlab/golden 0 2799 | grep ^TR > /tmp/ref.txt"
      echo "      python tools/diff_trace.py ${GOLDEN_DIR}/golden/rtl_trace.txt /tmp/ref.txt 5 1"
      ;;
  all)
      $0 i2c_master && echo && $0 mpu6050 && echo && $0 osc_dds && echo && $0 hit_detector
      ;;
  *)
      echo "用法: $0 {i2c_master|mpu6050|osc_dds|hit_detector|trace|rom|all}"; exit 2;;
esac
