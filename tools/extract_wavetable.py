#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extract_wavetable.py —— 从真实鼓声样本提取「单周期波表」，供 FPGA 波表合成器用。

这是"波表合成"的正确做法：只取鼓皮振动的一个周期（几百点），
衰减尾巴、音高下滑、力度全部由 RTL 现场算，不把整段录音放进 ROM。

输入：fpga_ready/wav16/ 下的 kick_v3 / snare_v3（中力度）
输出：
  1) 分析报告（起音点、基频、周期样本数）
  2) rtl/src/wavetable/*.hex —— Gowin ROM 初始化（有符号 Q15 补码，每行 4 位十六进制）
"""
import wave, os, sys
import numpy as np

SRC = r"C:/Users/XuXia/Doubao/chats/2026-09-21/new-chat/fpga_instrument_samples/fpga_ready/wav16"
OUT = r"D:/GitHub/fpga-music-engine/rtl/src/wavetable"
WAVETABLE_N = 256          # 提取的单周期点数
ROM_N       = 1024         # ROM 深度：padding 到 1024 点，让 Gowin 自动映射 BSRAM
                           # （256 点会被映射成 LUT 组合逻辑，$readmemh 初始化会丢）

def load(name):
    with wave.open(os.path.join(SRC, name + ".wav")) as w:
        fs = w.getframerate()
        n = w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype=np.int16)
    return data.astype(np.float64), fs

def find_onset(x, frac=0.15):
    """起音点：幅度首次超过峰值 frac 的位置"""
    peak = np.max(np.abs(x))
    idx = np.argmax(np.abs(x) > frac * peak)
    return int(idx)

def estimate_f0(x, fs, lo=25.0, hi=500.0):
    """自相关估计基频"""
    x = x - np.mean(x)
    r = np.correlate(x, x, mode="full")[len(x) - 1:]
    lo_idx = int(fs // hi)
    hi_idx = int(fs // lo)
    if hi_idx <= lo_idx + 1:
        return 0.0, 0
    seg = r[lo_idx:hi_idx]
    lag = int(np.argmax(seg)) + lo_idx
    return fs / lag, lag

def extract_cycle(x, fs, onset, f0):
    """从起音点取一个基频周期（鼓皮固有振动），重采样到 256 点。
    不跳过瞬态——起音第一拍就是鼓皮低频振动，音高下滑交给 RTL 现场做。"""
    if f0 <= 0:
        return None
    period = fs / f0
    start = onset
    end = start + int(round(period))
    if end >= len(x):
        end = len(x) - 1
        start = max(0, end - int(round(period)))
    seg = x[start:end]
    # 重采样到 256 点（线性插值）
    xs = np.linspace(0, len(seg) - 1, WAVETABLE_N)
    wave = np.interp(xs, np.arange(len(seg)), seg)
    wave = wave - np.mean(wave)                    # 去直流
    m = np.max(np.abs(wave))
    if m < 1e-6:
        return None
    return wave / m                               # 归一化到 ±1

def to_hex(wave):
    lines = []
    for v in wave:
        q = int(round(v * 32767))
        if q < 0:
            q += 65536
        lines.append(f"{q:04X}")
    return "\n".join(lines) + "\n"

def main():
    os.makedirs(OUT, exist_ok=True)
    report = []
    # (name, 基频搜索下限, 上限)  —— 底鼓是低频，军鼓是鼓皮中频
    for name, lo, hi in [("kick_v3", 30.0, 250.0), ("snare_v3", 100.0, 300.0)]:
        x, fs = load(name)
        onset = find_onset(x)
        xseg = x[onset:onset + fs]                 # 起音后 1 秒内估基频
        f0, lag = estimate_f0(xseg, fs, lo=lo, hi=hi)
        wave = extract_cycle(x, fs, onset, f0)
        if wave is None:
            report.append(f"{name}: 基频估计失败")
            continue
        # 输出 hex（重复到 ROM_N 点，保证进 BSRAM）
        path = os.path.join(OUT, name.split("_")[0] + ".hex")
        wave1024 = np.tile(wave, ROM_N // WAVETABLE_N)
        with open(path, "w") as f:
            f.write(to_hex(wave1024))
        report.append(
            f"{name}: onset={onset}样本  f0={f0:.1f}Hz  周期={fs/f0:.1f}样本  "
            f"波表={path} ({WAVETABLE_N}点×{ROM_N//WAVETABLE_N}重复)"
        )
        # 打印波形前 8 个值，方便肉眼核对
        print(f"[{name}] f0={f0:.1f}Hz  first8={[round(v,3) for v in wave[:8]]}")
    print("\n".join(report))

if __name__ == "__main__":
    main()
