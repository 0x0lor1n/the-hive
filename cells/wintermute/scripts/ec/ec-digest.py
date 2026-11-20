#!/usr/bin/env python3
"""Verify and recompute the two SHA-256 digests of the MEC EC image.

Both are plain digests over fixed ranges of the EC region (the board file
holds them): one over the PHCM header, stored right after it, one over the
code+data payload, stored right after that. The PL and fan tables sit inside
the payload range, so any edit there needs the payload digest rewritten; the
header is never touched.

    ec-digest check <image> [offset]    verify both digests; names the payload
                                        if the board file knows it
    ec-digest fix   <image> [offset]    rewrite the payload digest in place

Reads the image and the board file. fix writes 32 bytes into the image.
"""
import hashlib
import os
import sys

# No __pycache__ in the checkout: the devshell copies the tree into the store.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import board  # noqa: E402

TOOL = "ec-digest"


def digests(d, o, ec):
    h0, h1 = ec["header"]
    b0, b1 = ec["body"]
    return hashlib.sha256(d[o + h0:o + h1]).digest(), hashlib.sha256(d[o + b0:o + b1]).digest()


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "fix"):
        board.usage(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    try:
        o = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
    except ValueError:
        board.usage(__doc__)
    b = board.load(TOOL)
    d = bytearray(open(path, "rb").read())
    ec = board.header_ok(TOOL, b, d, o, path)
    h1, h2 = digests(d, o, ec)
    ok1 = d[o + ec["header"][1]:o + ec["header"][1] + 32] == h1
    ok2 = d[o + ec["body"][1]:o + ec["body"][1] + 32] == h2
    known = b["ec"]["payloads"].get(h2.hex(), "")
    print(f"header  {h1.hex()} {'ok' if ok1 else 'MISMATCH'}")
    print(f"payload {h2.hex()} {'ok' if ok2 else 'MISMATCH'}" + (f"  {known}" if known and ok2 else ""))
    if cmd == "fix":
        if not ok1:
            sys.exit(f"{TOOL}: not started, header digest mismatch; the header must stay as the board file has it")
        d[o + ec["body"][1]:o + ec["body"][1] + 32] = h2
        open(path, "wb").write(d)
        print(f"{TOOL}: OK payload digest written")
        return
    sys.exit(0 if ok1 and ok2 else 1)


if __name__ == "__main__":
    main()
