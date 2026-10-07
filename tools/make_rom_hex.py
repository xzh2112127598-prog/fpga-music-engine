#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_rom_hex.py —— 生成 RTL 仿真用的波表 .hex（$readmemh 直接读），并自校验。

表内容与 MATLAB lib/make_sine_table.m / make_noise_table.m 完全一致：
    sine : round(sin(2*pi*(0:n-1)/n) * 32767)
输出写进 sim/teamB/drum_sim_matlab/golden/，供 rtl/tb 的 $readmemh 使用。
生成后会用定点 DDS 跑一遍，与 golden/dds_440_out.txt / dds_440_ip_out.txt 逐个样本比对，
不一致就报错 —— 保证"表没生成错"这件事不用靠人眼。
"""
import os, sys, math

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLDEN = os.path.join(REPO, 'sim', 'teamB', 'drum_sim_matlab', 'golden')


def make_sine_table(n):
    return [round(math.sin(2 * math.pi * i / n) * 32767) for i in range(n)]


def make_noise_table(n, seed=20251005):
    """MATLAB lib/make_noise_table.m：23bit Galois LFSR，多项式 x^23+x^18+1
    每输出 16bit 推进 16 个 LFSR 时钟。波表是"噪声振荡器的波形 ROM"，
    不是预录音频 —— 这一点答辩要主动说明。"""
    reg = seed
    mask = (1 << 22) + (1 << 17)
    rom = []
    for _ in range(n):
        w = 0
        for b in range(16):
            lsb = reg & 1
            reg >>= 1
            if lsb:
                reg ^= mask
            w += lsb * (1 << (16 - 1 - b))
        if w >= 32768:
            w -= 65536
        rom.append(w)
    return rom


def write_hex(path, vals, width=16, signed=True):
    ndig = width // 4
    with open(path, 'w') as f:
        for v in vals:
            if signed and v < 0:
                v += (1 << width)
            f.write('%0*X\n' % (ndig, v))


def dds_render(rom, n, ftw, phase_bits=32, ipolate=False):
    """MATLAB lib/dds_render.m 与 dds_render_ip.m 的定点复现"""
    naddr = (len(rom) - 1).bit_length()          # log2
    shift = phase_bits - naddr
    wrap = 1 << phase_bits
    phase = 0
    y = []
    for _ in range(n):
        addr = phase >> shift
        if not ipolate:
            y.append(rom[addr])
        else:
            frac = phase - (addr << shift)
            a0 = rom[addr]
            a1 = rom[(addr + 1) % len(rom)]
            # round(x) 半值远离零：|x| 先加 0.5 再向下取整，最后还原符号
            num = (a0 << shift) + frac * (a1 - a0)
            half = 1 << (shift - 1)
            if num >= 0:
                y.append((num + half) >> shift)
            else:
                y.append(-(((-num) + half) >> shift))
        phase += ftw
        if phase >= wrap:
            phase -= wrap
    return y


def load_txt(path):
    with open(path) as f:
        return [int(float(l)) for l in f if l.strip()]


def main():
    fs, pb = 48000, 32
    ok = True

    # ---- 正弦表 ----
    sine = make_sine_table(1024)
    sp = os.path.join(GOLDEN, 'sine_1024.hex')
    write_hex(sp, sine)
    print('已写 %s（%d 点）' % (sp, len(sine)))

    ftw440 = round(440 * (1 << pb) / fs)
    print('440Hz FTW = %d (0x%08X)' % (ftw440, ftw440))
    for name, ipo in (('dds_440_out.txt', False), ('dds_440_ip_out.txt', True)):
        ok &= check(name, sine, ftw440, pb, ipo)

    # ---- 噪声表（同一个 DDS，只是换表、换地址位宽）----
    noise = make_noise_table(8192)
    np_ = os.path.join(GOLDEN, 'noise_8192.hex')
    write_hex(np_, noise)
    print('已写 %s（%d 点）' % (np_, len(noise)))
    # main_drum_engine: dds_render(noise_rom, 0.5*Fs, P.noise_ftw=2^19, 0, 32)
    ok &= check('noise_out.txt', noise, 1 << 19, pb, False)

    sys.exit(0 if ok else 1)


def check(name, rom, ftw, pb, ipo):
    gp = os.path.join(GOLDEN, name)
    if not os.path.exists(gp):
        print('跳过 %s（文件不存在）' % name)
        return True
    ref = load_txt(gp)
    got = dds_render(rom, len(ref), ftw, pb, ipo)
    bad = sum(1 for a, b in zip(ref, got) if a != b)
    print('%s: %d 样本，不一致 %d 个 -> %s'
          % (name, len(ref), bad, '一致' if bad == 0 else '不一致'))
    if bad:
        for i, (a, b) in enumerate(zip(ref, got)):
            if a != b:
                print('  首个差异 @%d: 期望 %d 实得 %d' % (i, a, b))
                break
        return False
    return True


if __name__ == '__main__':
    main()
