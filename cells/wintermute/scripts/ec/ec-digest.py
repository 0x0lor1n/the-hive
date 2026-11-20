#!/usr/bin/env python3
"""Verify and recompute the two SHA-256 digests of the MEC EC image.

Both are plain digests over fixed ranges of the EC region:
  stored at 0x1040 = SHA-256(0x1000..0x1040)   PHCM header, first 0x40 bytes
  stored at 0x27240 = SHA-256(0x1080..0x27240) code+data payload

The PL1 tables (0x211a8..0x24b8c) sit inside the payload range, so any edit
there needs the second digest rewritten; the header is untouched.

    ec-digest check <image> [offset]    verify both digests
    ec-digest fix   <image> [offset]    rewrite the payload digest in place
"""
import hashlib
import sys

HDR, HDR_END, DG1 = 0x1000, 0x1040, 0x1040
BODY, BODY_END, DG2 = 0x1080, 0x27240, 0x27240


def digests(d, o):
    return (
        hashlib.sha256(d[o + HDR:o + HDR_END]).digest(),
        hashlib.sha256(d[o + BODY:o + BODY_END]).digest(),
    )


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "fix"):
        sys.exit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    o = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
    d = bytearray(open(path, "rb").read())
    h1, h2 = digests(d, o)
    ok1 = d[o + DG1:o + DG1 + 32] == h1
    ok2 = d[o + DG2:o + DG2 + 32] == h2
    print(f"header  {h1.hex()} {'ok' if ok1 else 'MISMATCH'}")
    print(f"payload {h2.hex()} {'ok' if ok2 else 'MISMATCH'}")
    if cmd == "fix":
        if not ok1:
            sys.exit("header digest mismatch: refusing, the header must stay stock")
        d[o + DG2:o + DG2 + 32] = h2
        open(path, "wb").write(d)
        print("payload digest written")
    sys.exit(0 if ok1 and ok2 else 1)


if __name__ == "__main__":
    main()
