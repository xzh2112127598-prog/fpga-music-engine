# -*- coding: utf-8 -*-
"""
verify_flute_synth.py — 电子笛子 MATLAB 仿真算法的独立数值验证
与 electronic_flute_sim.m 的参数与公式完全一致（numpy + scipy）
用途：在无法启动 MATLAB 批处理的环境下交叉验证算法正确性，
      并生成同结构的预览 WAV 供先听效果。
"""
import numpy as np
import wave
from scipy.signal import butter, lfilter

Fs = 48000
A1, A2, A3 = 1.0, 0.50, 0.30
NOISE_GAIN, NOISE_BAND = 0.05, (1500.0, 6000.0)
VIB_RATE, VIB_DEPTH = 5.5, 0.004
ATT, REL, GAP = 0.060, 0.100, 0.030
rng = np.random.default_rng(2026)

# 指法表: (简谱, 指法6bit, 频率Hz, 超吹) —— 与 .m 中 ft 一致
TABLE = [
    ('5',  '000000', 587.33,  0),
    ('6',  '100000', 659.26,  0),
    ('7',  '110000', 739.99,  0),
    ('1',  '111000', 783.99,  0),
    ('2',  '111100', 880.00,  0),
    ('3',  '111110', 987.77,  0),
    ('4',  '111111', 1046.50, 0),
    ('5^', '000000', 1174.66, 1),
]

def lookup(fing, ob):
    for jp, fg, f0, o in TABLE:
        if fg == fing and o == ob:
            return jp, f0
    raise ValueError('指法未找到: %s ob=%d' % (fing, ob))

def breath_profile(dur, level):
    """与 breath_profile.m 一致：起音-保持-收音，线性包络"""
    n = max(1, int(round(dur * Fs)))
    na = max(1, int(round(ATT * Fs)))
    nr = max(1, int(round(REL * Fs)))
    ns = max(0, n - na - nr)
    env = np.concatenate([np.linspace(0, 1, na), np.ones(ns), np.linspace(1, 0, nr)])
    return (level * env[:n])

def synth_flute_tone(f0, breath, overblow):
    """与 synth_flute_tone.m 一致：基波+2/3次谐波，相位累加，气流非线性控制音量"""
    n = breath.size
    t = np.arange(n) / Fs
    amps = np.array([1.0, 0.60, 0.40]) if overblow else np.array([A1, A2, A3])
    inst_f = f0 * (1 + VIB_DEPTH * np.sin(2 * np.pi * VIB_RATE * t))
    phase = 2 * np.pi * np.cumsum(inst_f) / Fs
    y = amps[0] * np.sin(phase) + amps[1] * np.sin(2 * phase) + amps[2] * np.sin(3 * phase)
    return y * (breath ** 1.2) / amps.sum()

def synth_breath_noise(n, breath):
    """与 synth_breath_noise.m 一致：白噪声->4阶butter带通->气流平方调制->起音增强"""
    if NOISE_GAIN <= 0 or n < 16:
        return np.zeros(n)
    b, a = butter(4, [NOISE_BAND[0] / (Fs / 2), NOISE_BAND[1] / (Fs / 2)], 'bandpass')
    noise = lfilter(b, a, rng.standard_normal(n))
    env = breath ** 2
    na = min(n, int(round(0.05 * Fs)))
    if na > 1:
        env = env * np.concatenate([np.linspace(2.5, 1, na), np.ones(n - na)])
    return NOISE_GAIN * noise * env / (np.max(np.abs(noise)) + 1e-12)

# ============ 验证1: 指法-频率 ============
print('=== 验证1 指法-频率（筒音作5, D调）===')
for jp, fg, f0, ob in TABLE:
    print('  %-3s %s  %8.2f Hz' % (jp, fg, f0))

# ============ 验证2: 单音谐波合成（第一音 5/D5）============
f0 = TABLE[0][2]
breath = breath_profile(0.40, 0.85)
y = synth_flute_tone(f0, breath, False)
seg = y[int(0.15 * Fs):int(0.30 * Fs)]
N = seg.size
w = 0.5 * (1 - np.cos(2 * np.pi * np.arange(N) / (N - 1)))   # 与 .m 相同的手写 Hann
X = np.fft.rfft(seg * w, n=1 << 16)
f_ax = np.fft.rfftfreq(1 << 16, 1 / Fs)
mag = np.abs(X)
mag = mag / mag.max()
print('=== 验证2 谐波合成（期望 587.33/1174.66/1761.99 Hz，幅度比 1:0.50:0.30）===')
ok = True
for h, exp in [(1, 1.00), (2, 0.50), (3, 0.30)]:
    m = (f_ax >= h * f0 - 40) & (f_ax <= h * f0 + 40)
    idx = np.where(m)[0]
    i = idx[np.argmax(mag[m])]
    ratio_ok = abs(mag[i] / exp - 1) < 0.10
    ok = ok and ratio_ok
    print('  %d次谐波 实测 %7.2f Hz  幅度比 %.3f (期望 %.2f) %s' %
          (h, f_ax[i], mag[i], exp, 'OK' if ratio_ok else 'FAIL'))

# ============ 验证3: 气声噪声频带 ============
noise = synth_breath_noise(y.size, breath)
segN = noise[int(0.15 * Fs):int(0.30 * Fs)]
XN = np.fft.rfft(segN * np.hanning(segN.size))
fN = np.fft.rfftfreq(segN.size, 1 / Fs)
inb = np.sum(np.abs(XN)[(fN >= NOISE_BAND[0]) & (fN <= NOISE_BAND[1])] ** 2)
outb = np.sum(np.abs(XN)[(fN < NOISE_BAND[0]) | (fN > NOISE_BAND[1])] ** 2)
ratio = inb / (outb + 1e-12)
print('=== 验证3 气声频带（带通 1.5k~6kHz）===')
print('  带内/带外能量比 = %.2f (>>1 表示气声集中于中高频) %s' % (ratio, 'OK' if ratio > 3 else 'FAIL'))

# ============ 验证4: 八度音阶整曲 + 导出预览 WAV ============
score = [
    ('000000', 0, 0.40, 0.85), ('100000', 0, 0.40, 0.85),
    ('110000', 0, 0.40, 0.85), ('111000', 0, 0.40, 0.85),
    ('111100', 0, 0.40, 0.85), ('111110', 0, 0.40, 0.85),
    ('111111', 0, 0.40, 0.85), ('000000', 1, 0.55, 1.00),
]
y_all = np.array([])
breath_all = np.array([])
for fing, ob, dur, lvl in score:
    jp, f0n = lookup(fing, ob)
    br = breath_profile(dur, lvl)
    yn = synth_flute_tone(f0n, br, ob)
    ns = synth_breath_noise(br.size, br)
    x = yn + ns
    g = np.zeros(int(round(GAP * Fs)))
    y_all = np.concatenate([y_all, x, g])
    breath_all = np.concatenate([breath_all, br, g])
y_all = 0.9 * y_all / (np.max(np.abs(y_all)) + 1e-12)
print('=== 验证4 整曲（8音阶上行 + 吐音）===')
print('  时长 %.2fs  采样点数 %d  波形峰值 %.2f (期望0.90) %s' %
      (y_all.size / Fs, y_all.size, np.max(np.abs(y_all)),
       'OK' if abs(np.max(np.abs(y_all)) - 0.9) < 0.01 else 'FAIL'))
print('  气流峰值 %.2f (期望1.00, 末音5^超吹气流=1.00) %s' %
      (breath_all.max(), 'OK' if abs(breath_all.max() - 1.00) < 0.01 else 'FAIL'))

pcm = np.clip(np.round(y_all * 32767), -32768, 32767).astype('<i2')
with wave.open('electronic_flute_preview.wav', 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(Fs)
    wf.writeframes(pcm.tobytes())
print('  已导出 electronic_flute_preview.wav (16bit/48kHz, 与 MATLAB 脚本同结构)')
print('ALL_CHECKS_DONE')
