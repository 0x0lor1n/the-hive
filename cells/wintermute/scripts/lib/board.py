#!/usr/bin/env python3
"""The board file: scripts/boards/$BOARD.toml, every board-specific value the tools use.

    board.py <tool> <key> [key..]    one value per line, for shell callers;
                                     a list prints comma-joined, `a.b.1` indexes one

Reads the board file. Writes nothing.
"""
import hashlib
import os
import sys
import tomllib
from typing import NoReturn

HERE = os.path.dirname(os.path.abspath(__file__))


def usage(doc) -> NoReturn:
    print(doc.strip(), file=sys.stderr)
    sys.exit(2)


def load(tool):
    name = os.environ.get("BOARD", "xeon")
    path = os.path.join(HERE, "..", "boards", name + ".toml")
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except FileNotFoundError:
        sys.exit(f"{tool}: not started, no board file for BOARD={name}")


def header_ok(tool, board, d, o, path):
    """Refuse an image whose EC header is not this board's; returns the body range and load delta."""
    ec = board["ec"]
    h0, h1 = ec["header"]
    if len(d) < o + ec["size"]:
        sys.exit(f"{tool}: not started, {path} is shorter than an EC region at offset {o:#x}")
    if hashlib.sha256(d[o + h0:o + h1]).hexdigest() != ec["header_sha256"]:
        sys.exit(f"{tool}: not started, {path} header digest is not {board['name']}'s EC")
    return ec


def get(board, key):
    v = board
    for k in key.split("."):
        v = v[int(k)] if isinstance(v, list) else v[k]
    return ",".join(str(x) for x in v) if isinstance(v, list) else str(v)


def main():
    if len(sys.argv) < 3:
        usage(__doc__)
    board = load(sys.argv[1])
    for key in sys.argv[2:]:
        try:
            print(get(board, key))
        except (KeyError, IndexError, ValueError):
            sys.exit(f"{sys.argv[1]}: not started, no {key} in the {board['name']} board file")


if __name__ == "__main__":
    main()
