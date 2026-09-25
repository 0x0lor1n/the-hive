# Builds a .tdesktop-theme from the pinned Telegram source: every key of
# lib_ui colors.palette, valued as the bundled night theme does, each literal
# snapped to the nearest palette colour (OKLCh, alpha kept); pins win.
# argv: colors.palette night.tdesktop-theme colors.json pins.json out
import json, math, re, struct, sys, zipfile, zlib

palette_path, night_path, colors_path, pins_path, out = sys.argv[1:]
colors = json.load(open(colors_path))
pins = json.load(open(pins_path))
LINE = re.compile(r"^([A-Za-z]\w*)\s*:\s*([^;]+);")
HEX = re.compile(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$")


def parse(text):
    return [m.groups() for m in map(LINE.match, text.splitlines()) if m]


base = [(k, v.strip()) for k, v in parse(open(palette_path).read())]
with zipfile.ZipFile(night_path) as z:
    night = dict((k, v.strip()) for k, v in parse(z.read("colors.tdesktop-theme").decode()))
keys = [k for k, _ in base]
unknown = set(pins) - set(keys)
if unknown:
    sys.exit(f"pins not in colors.palette: {sorted(unknown)}")


def oklch(h):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(int(h[i : i + 2], 16)) for i in (0, 2, 4))
    l, m, s = (
        x ** (1 / 3)
        for x in (
            0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
            0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
            0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
        )
    )
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.atan2(bb, a)


ours = {h: oklch(h) for h in set(colors.values())}


def snap(h):
    L1, C1, H1 = oklch(h)

    def d(t):
        L2, C2, H2 = t
        dh = 2 * math.sqrt(C1 * C2) * math.sin((H1 - H2) / 2)
        return (L1 - L2) ** 2 + (2 * (C1 - C2)) ** 2 + (3 * dh) ** 2

    return min(sorted(ours), key=lambda k: d(ours[k]))


lines, done = [], set()
for k, default in base:
    if k in pins:
        v = "#" + pins[k]
    else:
        # `#lit | key`: a custom theme that omits the key gets `key`, so
        # follow the reference, not the light-theme literal.
        v = night.get(k) or default.split("|")[-1].strip()
        m = HEX.match(v)
        if m:
            v = "#" + snap(m.group(1).lower()) + (m.group(2) or "")
        elif v not in done:
            sys.exit(f"{k}: {v!r} is neither a colour nor an earlier key")
    lines.append(f"{k}: {v};")
    done.add(k)


def png(rgb, n=8):
    row = b"\0" + bytes(rgb) * n
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(row * n))
        + chunk(b"IEND", b"")
    )


bg = pins["windowBg"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr(zipfile.ZipInfo("colors.tdesktop-theme", (1980, 1, 1, 0, 0, 0)), "\n".join(lines) + "\n")
    # Without a background Telegram keeps the previous wallpaper; a flat tile
    # makes the chat area the palette bg.
    z.writestr(zipfile.ZipInfo("tiled.png", (1980, 1, 1, 0, 0, 0)), png(bytes.fromhex(bg)))
