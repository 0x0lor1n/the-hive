#!/usr/bin/env bash
# Produce subset Iosevka webfonts from the nixpkgs iosevka-bin package.
#
# Why this exists rather than committing binaries blindly: iosevka-bin ships
# 426 MB of .ttc TrueType Collections (48 MB per weight) which are unusable as
# webfonts. This extracts one face, subsets it to the characters this site can
# actually render, and emits WOFF2 - about 17 KB per weight.
#
# Only needed when the glyph set or the font version changes. The resulting
# .woff2 files live in static/fonts/ and are what the site actually serves, so
# the 426 MB package is a BUILD-time dependency only - never needed on the
# server. That is why it is not in the default devShell.

set -euo pipefail

OUT="${OUT:-static/fonts}"
FACE="${FACE:-0}" # 0 = "Iosevka", 1 = "Iosevka Term", 2 = "Iosevka Fixed"

command -v python3 >/dev/null || {
  echo "python3 with fontTools required" >&2
  exit 1
}

IOSEVKA="${IOSEVKA:-}"
if [ -z "$IOSEVKA" ]; then
  echo "  fetching iosevka-bin (426 MB, cached after the first run)..."
  IOSEVKA="$(nix build --no-link --print-out-paths nixpkgs#iosevka-bin)"
fi
TTC_DIR="$IOSEVKA/share/fonts/truetype"
[ -d "$TTC_DIR" ] || {
  echo "no truetype dir in $IOSEVKA" >&2
  exit 1
}

mkdir -p "$OUT"

OUT="$OUT" TTC_DIR="$TTC_DIR" FACE="$FACE" python3 <<'PY'
import os
from fontTools.ttLib import TTCollection
from fontTools import subset

OUT, TTC_DIR, FACE = os.environ["OUT"], os.environ["TTC_DIR"], int(os.environ["FACE"])

# Every character the site can render. Anything outside this set falls back to
# the next family in the stack, per glyph - degraded but never broken.
CHARS = set(
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "íóëéèàçüöäñ"          # Hisilome, Chene-Bougeries, etc
    "—–‘’“”…"   # em/en dash, curly quotes, ellipsis
    "▸●■▶▓·←"   # UI markers: play, on-air, blocks
)

for style in ("Regular", "Bold"):
    src = f"{TTC_DIR}/Iosevka-{style}.ttc"
    face = TTCollection(src).fonts[FACE]
    tmp = f"{OUT}/.tmp-{style}.ttf"
    face.save(tmp)

    opts = subset.Options(flavor="woff2", desubroutinize=True)
    opts.layout_features = ["kern", "liga", "calt", "tnum"]  # tnum: schedule columns
    font = subset.load_font(tmp, opts)
    sub = subset.Subsetter(options=opts)
    sub.populate(unicodes=[ord(c) for c in CHARS])
    sub.subset(font)

    dst = f"{OUT}/iosevka-{style.lower()}.woff2"
    subset.save_font(font, dst, opts)
    os.remove(tmp)
    print(f"  {style:8} -> {dst}  {os.path.getsize(dst)/1024:.1f} KB  ({len(CHARS)} glyphs)")
PY
