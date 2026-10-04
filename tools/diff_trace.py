#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
diff_trace.py —— 把 RTL 逐样本 trace 与 ref_hit.py 黄金 trace 对比，找第一次分叉。
用法：
    python diff_trace.py <rtl_trace.txt> <ref_trace.txt> [上下文行数]
RTL trace 里同一 idx 可能出现多行（同一拍的更新前后各一次），只取第一次出现的。
"""
import sys

def load(path, tag):
    rows = {}
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) < 10 or p[0] != tag:
                continue
            i = int(p[1])
            if i not in rows:
                v = [int(x) for x in p[2:11]]
                # 状态编码映射：RTL 是 0=IDLE 1=TRACK 2=SQRT 3=REFR，
                # 黄金模型只有 0=IDLE 1=TRACK 2=REFR（开方是瞬间完成的）。
                # 把 RTL 的 SQRT/REFR 统一映射成 2，否则整段不应期都会被误报。
                if v[4] >= 2:
                    v[4] = 2
                rows[i] = v
    return rows, sorted(rows)

def main():
    rtl, rord = load(sys.argv[1], 'TR')
    ref, ford = load(sys.argv[2], 'TR')
    ctx = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    skip = int(sys.argv[4]) if len(sys.argv) > 4 else 1   # idx=0 是预置基线的口径差，跳过

    common = [i for i in sorted(set(rtl) & set(ref))]
    print("RTL 行数 %d，参考行数 %d，共有样本 %d" % (len(rtl), len(ref), len(common)))

    names = ['dx', 'dy', 'dz', 'magsq', 'st', 'wcnt', 'bx', 'by', 'bz']
    bad = []
    for i in common:
        if i < skip:
            continue
        d = [n for n, a, b in zip(names, rtl[i], ref[i]) if a != b]
        if d:
            bad.append((i, d))
    print("不一致样本数：%d" % len(bad))
    if not bad:
        print("=== 完全一致 ===")
        return
    first = bad[0][0]
    print("第一次分叉：idx=%d  差异字段=%s" % (first, ','.join(bad[0][1])))
    print("%5s %8s %8s %8s %12s %3s %5s %8s %8s %8s   %s"
          % ('idx', 'dx', 'dy', 'dz', 'magsq', 'st', 'wcnt', 'bx', 'by', 'bz', 'src'))
    for i in range(max(0, first - ctx), min(max(common), first + ctx + 1)):
        for src, tab in (('REF', ref), ('RTL', rtl)):
            if i in tab:
                v = tab[i]
                print("%5d %8d %8d %8d %12d %3d %5d %8d %8d %8d   %s"
                      % (i, v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], src))

if __name__ == '__main__':
    main()
