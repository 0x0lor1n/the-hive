#!/usr/bin/env python3
"""Dump / patch the EC power-limit and fan tables of an EC image.

The board file holds the addresses; the layout below is the xeon one.
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
    ec-tables fan <image> [offset] [idx,idx..]
        dump fan curves, default the board's quiet CPU ones: idx, row, mode,
        sensor, VA, crit, the steps as down/up:rpm, and the 24 step bytes in
        the form fan-set takes
    ec-tables fan-set <image> <offset> <idx,idx..> <old-hex> <new-hex>
        replace the 24 step bytes (+8..+32) of the given structs, in place;
        refuses unless every struct holds exactly <old-hex>

Fan curves: 0xF3BF8 holds 320 pointers, idx = row*20 + mode*5 + sensor with
row = (batt << 2) | (board << 1) | ac (0xECD30), mode 0 bal 1 cool 2 quiet 3
perf, sensor 0 cpu 1 skin 2 mem 3 ngff 4 gpu. Struct 0x28: +8 six {s8 down, s8 up, u16 rpm (low 14 bits)}, +0x27 crit.
Our board on AC is row 11 or 15 (batt = ADC strap via 0xDF0A0); their quiet
CPU structs are byte-identical, so both get the same edit.

Reads the image and the board file. patch, pl-set and fan-set write the
image in place; the payload digest is then stale until ec-digest fix.
"""
import os
import struct
import sys

# No __pycache__ in the checkout: the devshell copies the tree into the store.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import board  # noqa: E402

TOOL = "ec-tables"
MODES = ("bal", "cool", "quiet", "perf")
SENSORS = ("cpu", "skin", "mem", "ngff", "gpu")


class Image:
    def __init__(self, path, o):
        self.path, self.o = path, o
        self.d = bytearray(open(path, "rb").read())
        self.ec = board.header_ok(TOOL, board.load(TOOL), self.d, o, path)
        self.base = self.ec["load_va"] - self.ec["body"][0]  # VA - file offset

    def fan_struct(self, idx):
        if not 0 <= idx < 320:
            sys.exit(f"{TOOL}: not started, idx {idx}: the pointer table has 320 entries")
        va = struct.unpack_from("<I", self.d, self.o + self.ec["fan_ptrs"] - self.base + 4 * idx)[0]
        return va, self.o + va - self.base

    def fan_steps(self, p):
        d = self.d
        return [(struct.unpack_from("<b", d, p + 8 + 4 * k)[0], d[p + 9 + 4 * k],
                 struct.unpack_from("<H", d, p + 10 + 4 * k)[0] & 0x3FFF) for k in range(6)]

    def tables(self):
        out = []
        for i in range(16):
            va = struct.unpack_from("<I", self.d, self.o + self.ec["pl_ptrs"] - self.base + 4 * i)[0]
            p, rows = va - self.base, []
            while len(rows) < 64:
                r = self.d[self.o + p:self.o + p + 12]
                if len(r) < 12 or (rows and r[0] == 0 and r[1] == 0 and r[2] == 0):
                    break
                rows.append((p, r))
                p += 12
            out.append((i, va, rows))
        return out

    def write(self):
        open(self.path, "wb").write(self.d)


def ints(s):
    return [int(i) for i in s.split(",")]


def fan(img, idxs):
    for idx in idxs:
        va, p = img.fan_struct(idx)
        d = img.d
        print(f"idx {idx} row {idx // 20} {MODES[idx % 20 // 5]} {SENSORS[idx % 5]} {va:#x} crit {d[p + 0x27]}  "
              + " ".join(f"{a}/{b}:{r}" for a, b, r in img.fan_steps(p)) + f"  {d[p + 8:p + 32].hex()}")


def parse(a):
    """argv after the tool name -> (cmd, path, offset, the rest as ints / bytes); usage on anything else."""
    cmds = {"dump": (1, 2), "patch": (3, 4), "pl-get": (4, 4), "pl-set": (8, 8), "fan": (1, 3), "fan-set": (5, 5)}
    if len(a) < 2 or a[0] not in cmds or not cmds[a[0]][0] <= len(a) - 1 <= cmds[a[0]][1]:
        board.usage(__doc__)
    cmd, path = a[0], a[1]
    try:
        if cmd in ("dump", "fan"):
            return cmd, path, int(a[2], 0) if len(a) > 2 else 0, [ints(a[3])] if len(a) > 3 else []
        if cmd == "patch":
            return cmd, path, int(a[4], 0) if len(a) > 4 else 0, [int(a[2]), int(a[3])]
        o = int(a[2], 0)
        if cmd == "pl-get":
            return cmd, path, o, [ints(a[3]), int(a[4])]
        if cmd == "pl-set":
            return cmd, path, o, [ints(a[3]), int(a[4]), {"pl1": 2, "pl2": 3}[a[5]], int(a[6]), int(a[7]), int(a[8])]
        return cmd, path, o, [ints(a[3]), bytes.fromhex(a[4]), bytes.fromhex(a[5])]
    except (ValueError, KeyError):
        board.usage(__doc__)


def main():
    cmd, path, o, args = parse(sys.argv[1:])
    img = Image(path, o)
    if cmd == "dump":
        for i, va, rows in img.tables():
            pl1 = sorted({r[2] for _, r in rows})
            pl2 = sorted({r[3] for _, r in rows})
            print(f"{i:2} {va:#x} {len(rows):3} rows  PL1 {pl1}  PL2 {pl2}")
    elif cmd == "pl-get":
        idxs, k1 = args
        tabs = {i: rows for i, _, rows in img.tables()}
        if not all(i in tabs for i in idxs):
            sys.exit(f"{TOOL}: not started, a table index outside 0..15")
        hit = [r for i in idxs for _, r in tabs[i] if r[0] == k1]
        pairs = sorted({(r[2], r[3]) for r in hit})
        if len(pairs) != 1:
            sys.exit(f"{TOOL}: not started, {len(hit)} rows with k1 {k1} hold {len(pairs)} PL1/PL2 pairs {pairs}")
        print(*pairs[0], len(hit))
    elif cmd == "pl-set":
        idxs, k1, field, old, new, want = args
        name = "pl1" if field == 2 else "pl2"
        if not 0 < new < 256:
            sys.exit(f"{TOOL}: not started, new value must fit the row byte")
        tabs = {i: (va, rows) for i, va, rows in img.tables()}
        if not all(i in tabs for i in idxs):
            sys.exit(f"{TOOL}: not started, a table index outside 0..15")
        if len({tabs[i][0] for i in idxs}) != len(idxs):
            sys.exit(f"{TOOL}: not started, two indices share a table")
        hit = [(i, n, o + p) for i in idxs for n, (p, r) in enumerate(tabs[i][1]) if r[0] == k1]
        if len(hit) != want:
            sys.exit(f"{TOOL}: not started, {len(hit)} rows with k1 {k1}, expected {want}")
        for i, n, p in hit:
            if img.d[p + field] != old:
                sys.exit(f"{TOOL}: not started, table {i} row {n}: {name} is {img.d[p + field]}, not {old}")
            pl1, pl2 = (new, img.d[p + 3]) if field == 2 else (img.d[p + 2], new)
            if pl1 > pl2:
                sys.exit(f"{TOOL}: not started, table {i} row {n}: PL1 {pl1} above PL2 {pl2}")
        for i, n, p in hit:
            img.d[p + field] = new
            print(f"table {i} row {n} file {p:#x}: {bytes(img.d[p:p + 12]).hex()}")
        img.write()
        print(f"{TOOL}: OK {len(hit)} rows {name} {old} -> {new} W; now run ec-digest fix")
    elif cmd == "fan":
        fan(img, args[0] if args else img.ec["quiet_cpu"])
    elif cmd == "fan-set":
        idxs, old, new = args
        if len(old) != 24 or len(new) != 24:
            sys.exit(f"{TOOL}: not started, old/new must be 24 bytes (six steps)")
        ptrs = [img.fan_struct(i) for i in idxs]
        if len({va for va, _ in ptrs}) != len(ptrs):
            sys.exit(f"{TOOL}: not started, two indices share a struct")
        for (va, p), i in zip(ptrs, idxs):
            if bytes(img.d[p + 8:p + 32]) != old:
                sys.exit(f"{TOOL}: not started, idx {i} {va:#x}: {img.d[p + 8:p + 32].hex()} != old")
        for (va, p), i in zip(ptrs, idxs):
            img.d[p + 8:p + 32] = new
            print(f"idx {i} {va:#x}: " + " ".join(f"{x}/{y}:{r}" for x, y, r in img.fan_steps(p)))
        img.write()
        print(f"{TOOL}: OK {len(idxs)} structs written; now run ec-digest fix")
    else:
        old, new = args
        n = 0
        for _, _, rows in img.tables():
            for p, r in rows:
                if r[2] == old:
                    img.d[o + p + 2] = new
                    n += 1
        img.write()
        print(f"{TOOL}: OK {n} rows PL1 {old} -> {new} W; now run ec-digest fix")


if __name__ == "__main__":
    main()
