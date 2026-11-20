#!/usr/bin/env python3
"""Dump / patch the EC power-limit tables of the Precision 3520 EC image.

Layout (all VAs; file offset = VA - 0xCF000):
  0xF2128  per-battery-state array, +0x38 selector slot, +0x40 table pointer
  0xF2168  16 pointers to row tables, index = (a << 2) | (b << 1) | c with
           a = battery/adapter class (0xEFBF8+0x3A list: 3/2/1 by index),
           b = board class (0 = 15 W U-board, 1 = 35 W H-board, ours),
           c = AC bit from 0x40081300 bit 29 inverted
  row      12 bytes, +0 key k1, +2 PL1 W, +3 PL2 W, +4/+6 u16, +8 byte; the EC
           shifts each <<3 into PECI WrPkgConfig 0x1A/0x1B (1/8 W units)

    ec-tables dump <image> [offset]
    ec-tables patch <image> <old-W> <new-W> [offset]   PL1 only, in place
    ec-tables pl-get <image> <offset> <tbl,tbl..> <k1>
        print "<PL1> <PL2> <rows>" for the rows of the given tables whose key
        k1 matches; refuses unless they all hold the same pair
    ec-tables pl-set <image> <offset> <tbl,tbl..> <k1> <pl1|pl2> <old-W> <new-W> <rows>
        replace one field in the rows of the given tables whose key k1 matches,
        in place; refuses unless every such row holds <old-W>, their number is
        <rows>, and no row ends with PL1 above PL2
    ec-tables fan <image> [offset]                     dump our quiet CPU curves
    ec-tables fan-set <image> <offset> <idx,idx..> <old-hex> <new-hex>
        replace the 24 step bytes (+8..+32) of the given structs, in place;
        refuses unless every struct holds exactly <old-hex>

Fan curves: 0xF3BF8 holds 320 pointers, idx = row*20 + mode*5 + sensor with
row = (batt << 2) | (board << 1) | ac (0xECD30), mode 0 bal 1 cool 2 quiet 3
perf. Struct 0x28: +8 six {s8 down, s8 up, u16 rpm (low 14 bits)}, +0x27 crit.
Our board on AC is row 11 or 15 (batt = ADC strap via 0xDF0A0); their quiet
CPU structs are byte-identical, so both get the same edit.
"""
import struct
import sys

PTRS = 0xF2168
FAN_PTRS = 0xF3BF8
B = 0xD0000 - 0x1080  # VA - file offset: the body at 0x1080 loads to 0xD0000
QUIET_CPU = (11 * 20 + 2 * 5, 15 * 20 + 2 * 5)


def fan_struct(d, o, idx):
    va = struct.unpack_from("<I", d, o + FAN_PTRS - B + 4 * idx)[0]
    return va, o + va - B


def fan_steps(d, p):
    return [(struct.unpack_from("<b", d, p + 8 + 4 * k)[0], d[p + 9 + 4 * k],
             struct.unpack_from("<H", d, p + 10 + 4 * k)[0] & 0x3FFF) for k in range(6)]


def fan(d, o):
    for idx in QUIET_CPU:
        va, p = fan_struct(d, o, idx)
        print(f"row {idx // 20} quiet cpu {va:#x} crit {d[p + 0x27]}  "
              + " ".join(f"{a}/{b}:{r}" for a, b, r in fan_steps(d, p)))


def tables(d, o):
    out = []
    for i in range(16):
        va = struct.unpack_from("<I", d, o + PTRS - B + 4 * i)[0]
        p, rows = va - B, []
        while len(rows) < 64:
            r = d[o + p:o + p + 12]
            if len(r) < 12 or (rows and r[0] == 0 and r[1] == 0 and r[2] == 0):
                break
            rows.append((p, r))
            p += 12
        out.append((i, va, rows))
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    d = bytearray(open(path, "rb").read())
    if cmd == "dump":
        o = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
        for i, va, rows in tables(d, o):
            pl1 = sorted({r[2] for _, r in rows})
            pl2 = sorted({r[3] for _, r in rows})
            print(f"{i:2} {va:#x} {len(rows):3} rows  PL1 {pl1}  PL2 {pl2}")
        return
    if cmd == "pl-get":
        o = int(sys.argv[3], 0)
        idxs = [int(i) for i in sys.argv[4].split(",")]
        k1 = int(sys.argv[5])
        tabs = {i: rows for i, _, rows in tables(d, o)}
        hit = [r for i in idxs for _, r in tabs[i] if r[0] == k1]
        pairs = sorted({(r[2], r[3]) for r in hit})
        if len(pairs) != 1:
            sys.exit(f"{len(hit)} rows with k1 {k1} hold {len(pairs)} PL1/PL2 pairs {pairs}, refusing")
        print(*pairs[0], len(hit))
        return
    if cmd == "pl-set":
        o = int(sys.argv[3], 0)
        idxs = [int(i) for i in sys.argv[4].split(",")]
        k1, field = int(sys.argv[5]), {"pl1": 2, "pl2": 3}[sys.argv[6]]
        old, new, want = (int(a) for a in sys.argv[7:10])
        if not 0 < new < 256:
            sys.exit("new value must fit the row byte")
        tabs = {i: (va, rows) for i, va, rows in tables(d, o)}
        if len({tabs[i][0] for i in idxs}) != len(idxs):
            sys.exit("two indices share a table, refusing")
        hit = [(i, n, o + p) for i in idxs for n, (p, r) in enumerate(tabs[i][1]) if r[0] == k1]
        if len(hit) != want:
            sys.exit(f"{len(hit)} rows with k1 {k1}, expected {want}, refusing")
        for i, n, p in hit:
            if d[p + field] != old:
                sys.exit(f"table {i} row {n}: {sys.argv[6]} is {d[p + field]}, not {old}, refusing")
            pl1, pl2 = (new, d[p + 3]) if field == 2 else (d[p + 2], new)
            if pl1 > pl2:
                sys.exit(f"table {i} row {n}: PL1 {pl1} above PL2 {pl2}, refusing")
        for i, n, p in hit:
            d[p + field] = new
            print(f"table {i} row {n} file {p:#x}: {bytes(d[p:p + 12]).hex()}")
        open(path, "wb").write(d)
        print(f"{len(hit)} rows {sys.argv[6]} {old} -> {new} W; now run ec-digest fix")
        return
    if cmd == "fan-set":
        o = int(sys.argv[3], 0)
        idxs = [int(i) for i in sys.argv[4].split(",")]
        old, new = bytes.fromhex(sys.argv[5]), bytes.fromhex(sys.argv[6])
        if len(old) != 24 or len(new) != 24:
            sys.exit("old/new must be 24 bytes (six steps)")
        ptrs = [fan_struct(d, o, i) for i in idxs]
        if len({va for va, _ in ptrs}) != len(ptrs):
            sys.exit("two indices share a struct, refusing")
        for (va, p), i in zip(ptrs, idxs):
            if bytes(d[p + 8:p + 32]) != old:
                sys.exit(f"idx {i} {va:#x}: {d[p + 8:p + 32].hex()} != old, refusing")
        for (va, p), i in zip(ptrs, idxs):
            d[p + 8:p + 32] = new
            print(f"idx {i} {va:#x}: " + " ".join(f"{a}/{b}:{r}" for a, b, r in fan_steps(d, p)))
        open(path, "wb").write(d)
        print("written; now run ec-digest fix")
        return
    if cmd == "fan":
        fan(d, int(sys.argv[3], 0) if len(sys.argv) > 3 else 0)
        return
    if cmd != "patch":
        sys.exit(__doc__)
    old, new = int(sys.argv[3]), int(sys.argv[4])
    o = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0
    n = 0
    for _, _, rows in tables(d, o):
        for p, r in rows:
            if r[2] == old:
                d[o + p + 2] = new
                n += 1
    open(path, "wb").write(d)
    print(f"{n} rows PL1 {old} -> {new} W; now run ec-digest fix")


if __name__ == "__main__":
    main()
