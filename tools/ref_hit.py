#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ref_hit.py —— 用 Python 精确复现 MATLAB main_drum_engine.m Part 3 的定点敲击检测算法。
目的：给 RTL 对拍提供"每样本内部状态"的黄金参考，避免每次都启动 MATLAB。
算法必须与 MATLAB / hit_detector.v 三者一致，任何一边改动都要同步。
"""
import sys, os

def load_hex(path):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            v = int(line, 16)
            if v >= 0x8000:
                v -= 0x10000
            vals.append(v)
    return vals

def s32(v):
    return v - 0x100000000 if v >= 0x80000000 else v

def main(golden_dir, dump_from=None, dump_to=None):
    ax = load_hex(os.path.join(golden_dir, 'imu_ax.hex'))
    ay = load_hex(os.path.join(golden_dir, 'imu_ay.hex'))
    az = load_hex(os.path.join(golden_dir, 'imu_az.hex'))
    n = len(ax)

    LSBg = 2048
    THR_SQ = (LSBg // 2) ** 2
    WIN_CNT = 6
    REFR_CNT = 100
    VEL_K = (127 * 65536) // (10 * LSBg)
    DIR_TH_NUM = -(-(LSBg * 3) * WIN_CNT // 10)   # ceil
    print("THR_SQ=%d WIN_CNT=%d REFR_CNT=%d VEL_K=%d DIR_TH_NUM=%d"
          % (THR_SQ, WIN_CNT, REFR_CNT, VEL_K, DIR_TH_NUM))

    state = 0          # 0=IDLE 1=TRACK 2=REFR
    peak_sq = 0
    wcnt = 0
    ays = 0
    lastfire = -10**9
    bx, by, bz = ax[0], ay[0], az[0]
    events = []

    def fl_div32(v):
        # floor(v/32)，负数向下取整，与 Verilog 的 >>>5 一致
        return v // 32 if v >= 0 else -((-v + 31) // 32)

    trace = []
    for i in range(n):
        if i == 0:
            dx = dy = dz = 0
        else:
            dx = ax[i] - bx
            dy = ay[i] - by
            dz = az[i] - bz
        magsq = dx * dx + dy * dy + dz * dz
        fired = None
        # 进入本样本时的状态（对应 RTL 在 posedge 上读到的寄存器值）
        state_pre, wcnt_pre = state, wcnt
        if state == 0:
            if magsq > THR_SQ and (i - lastfire) > REFR_CNT:
                state = 1
                peak_sq = magsq
                wcnt = 0
                ays = 0
                hitstart = i
        elif state == 1:
            peak_sq = max(peak_sq, magsq)
            ays = ays + dy
            wcnt = wcnt + 1
            if wcnt >= WIN_CNT:
                if ays >= DIR_TH_NUM:
                    typ = 2
                elif ays <= -DIR_TH_NUM:
                    typ = 3
                else:
                    typ = 1
                peak = int(peak_sq ** 0.5)
                while (peak + 1) ** 2 <= peak_sq:
                    peak += 1
                while peak ** 2 > peak_sq:
                    peak -= 1
                rawv = min(127, (peak * VEL_K) // 65536)
                events.append((i, hitstart, typ, rawv))
                fired = (typ, rawv)
                state = 2
                lastfire = i
        else:
            if (i - lastfire) >= REFR_CNT:
                state = 0

        if dump_from is not None and dump_from <= i <= dump_to:
            trace.append((i, dx, dy, dz, magsq, state_pre, wcnt_pre, bx, by, bz))

        # 记录本样本结束后的状态（对应 RTL 下一拍读到的值），仅在 trace 模式下用
        post = (state, wcnt)

        bx = bx + fl_div32(ax[i] - bx)
        by = by + fl_div32(ay[i] - by)
        bz = bz + fl_div32(az[i] - bz)

    print("事件数 %d" % len(events))
    for e in events:
        print("  idx=%4d trig=%4d type=%d vel=%3d  (hex %08X)"
              % (e[0], e[1], e[2], e[3], (e[0] << 16) | (e[2] << 8) | e[3]))
    if trace:
        print("---- 逐样本 trace (i dx dy dz magsq state wcnt bx by bz) ----")
        for t in trace:
            print("TR %4d %6d %6d %6d %10d %d %d %6d %6d %6d" % t)
    return events

if __name__ == '__main__':
    gd = sys.argv[1] if len(sys.argv) > 1 else 'golden'
    a = int(sys.argv[2]) if len(sys.argv) > 2 else None
    b = int(sys.argv[3]) if len(sys.argv) > 3 else None
    main(gd, a, b)
