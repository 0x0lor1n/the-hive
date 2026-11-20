# Body of the ec-pl-build devshell command; devshells.nix sets $recon and $board ahead of it.

REGION=7340032 # 0x700000
SIZE=327680    # 0x50000

usage() {
  cat <<'EOF'
usage: ec-pl-build <n> <last-slice> <pl1-W> <pl2-W> <archive-dir> [dump]

Builds the EC region with PL1 / PL2 set in the rows a 130 W adapter selects,
from this clip session's dump (the one recon/<board>/pre<n>-*.bin, or [dump]),
plus the slice that undoes it.
  <last-slice>   the EC region last written to the chip; the dumped region
                 has to equal it below 0x45000
  <archive-dir>  gets a copy of the dump and of both slices
Writes ec-pre<n>.bin (the region as dumped) and ec-<n>-pl<W>.bin with .sha256
into recon/<board> and rehearses both chip writes on flashrom's dummy
programmer. No root, no programmer, nothing written to the
chip. A refusal leaves no slice behind.
The last line is "ec-pl-build: OK ..." or "ec-pl-build: STOPPED: ...".
EOF
}

work=
copied=
# Before the first write nothing is left behind; after it the dump copy in the archive stays.
refuse() {
  echo "ec-pl-build: not started, $*" >&2
  exit 1
}
die() {
  [ -z "$work" ] || rm -rf "$work"
  echo "ec-pl-build: STOPPED: $*${copied:+; the dump copy $copied stays}"
  exit 1
}
sha() { sha256sum "$1" | cut -d' ' -f1; }
# head first: tail | head would end in SIGPIPE, which pipefail turns into a failure.
slice() { head -c $((REGION + SIZE)) "$1" | tail -c "$SIZE" >"$2"; }
ndiff() { { cmp -l "$@" || true; } | wc -l; }

if [ $# -lt 5 ] || [ $# -gt 6 ]; then
  usage >&2
  exit 2
fi
for a in "$1" "$3" "$4"; do
  case "$a" in
  "" | 0?* | *[!0-9]*)
    usage >&2
    exit 2
    ;;
  esac
done
n=$1 ref=$2 pl1=$3 pl2=$4 fw=$5
# From the board file: the banks the EC rewrites, the payload digest offset, the
# tables a 130 W adapter selects on AC and the header digest of this EC build.
vals=$(python3 "$board" ec-pl-build ec.banks ec.body.1 ec.ac_tables ec.k1_130w ec.rows_130w ec.header_sha256) || exit 1
read -r BANKS DIGEST TABLES K1 ROWS HEADER <<EOF
$(printf '%s\n' "$vals" | tr '\n' ' ')
EOF
[ "$pl1" -le "$pl2" ] || refuse "PL1 $pl1 W above PL2 $pl2 W"
if [ $# -eq 6 ]; then
  dump=$6
else
  set -- "$recon"/pre"$n"-*.bin
  [ -e "$1" ] || refuse "no $recon/pre$n-*.bin; run dump pre$n first"
  [ $# -eq 1 ] || refuse "$# dumps match $recon/pre$n-*.bin; name one as the last argument"
  dump=$1
fi
what=pl$pl1
[ "$pl1" -eq "$pl2" ] || what=pl$pl1-$pl2
pre=$recon/ec-pre$n.bin
new=$recon/ec-$n-$what.bin
layout=$recon/layout.txt

for f in "$dump" "$dump.sha256" "$ref" "$layout"; do
  [ -r "$f" ] || refuse "cannot read $f"
done
{ [ -d "$fw" ] && [ -w "$fw" ]; } || refuse "$fw is not a writable directory"
for f in "$pre" "$new" "$fw/${pre##*/}" "$fw/${new##*/}"; do
  [ ! -e "$f" ] || refuse "$f exists, not overwriting"
done
[ "$(stat -c %s "$dump")" -eq 16777216 ] || refuse "$dump is not 16 MiB"
[ "$(stat -c %s "$ref")" -eq "$SIZE" ] || refuse "$ref is not a $SIZE-byte EC region slice"
# Not sha256sum -c: the file names the path dump wrote to, which a copy is not.
read -r want _ <"$dump.sha256" || true
[ "$want" = "$(sha "$dump")" ] || refuse "$dump does not match its .sha256"

echo "== dump $dump"
echo "== sha256 $(sha "$dump")"

# Off the checkout before any write: the dump is the only way back to this chip state.
name=${dump##*/}
if [ ! -e "$fw/$name" ]; then
  cp "$dump" "$fw/$name"
  cp "$dump.sha256" "$fw/$name.sha256"
  copied=$fw/$name
fi
[ "$(sha "$fw/$name")" = "$(sha "$dump")" ] || die "$fw/$name differs from the dump"
echo "== copy $fw/$name: same sha256"

work=$(mktemp -d)
slice "$dump" "$work/pre.bin"
[ "$(stat -c %s "$work/pre.bin")" -eq "$SIZE" ] || die "slice is not $SIZE bytes"

echo "== digests of the dumped region"
ec-digest check "$work/pre.bin" 0 >"$work/digest.txt" || {
  cat "$work/digest.txt"
  die "the dumped EC region fails its digests"
}
cat "$work/digest.txt"
grep -q "^header  $HEADER ok" "$work/digest.txt" || die "header digest is not $HEADER"
ec-digest check "$ref" 0 >/dev/null || die "$ref fails its digests"

drift=$(ndiff -n "$BANKS" "$work/pre.bin" "$ref")
[ "$drift" -eq 0 ] || die "$drift bytes below 0x45000 differ from ${ref##*/}: the live region drifted, diff it, do not force"
echo "== below 0x45000: identical to ${ref##*/}"
echo "== banks from 0x45000: $(ndiff -i "$BANKS" "$work/pre.bin" "$ref") bytes differ from it (expected, the EC writes there)"

cur=$(ec-tables pl-get "$work/pre.bin" 0 "$TABLES" "$K1") || die "cannot read the rows of tables $TABLES"
read -r old1 old2 rows <<EOF
$cur
EOF
[ "$rows" -eq "$ROWS" ] || die "$rows rows with k1 $K1 in tables $TABLES, expected $ROWS"
fields=0
[ "$pl1" -eq "$old1" ] || fields=$((fields + 1))
[ "$pl2" -eq "$old2" ] || fields=$((fields + 1))
[ "$fields" -gt 0 ] || die "the rows already hold PL1 $old1 W / PL2 $old2 W"

cp "$work/pre.bin" "$work/new.bin"
set_pl() {
  [ "$2" -eq "$3" ] || ec-tables pl-set "$work/new.bin" 0 "$TABLES" "$K1" "$1" "$2" "$3" "$ROWS" || die "pl-set $1 refused"
}
echo "== patch: PL1 $old1 -> $pl1 W, PL2 $old2 -> $pl2 W"
# pl-set refuses a row left with PL1 above PL2, so the field that keeps the order goes first.
if [ "$pl2" -ge "$old1" ]; then
  set_pl pl2 "$old2" "$pl2"
  set_pl pl1 "$old1" "$pl1"
else
  set_pl pl1 "$old1" "$pl1"
  set_pl pl2 "$old2" "$pl2"
fi
# fix exits 1 whenever the payload digest was stale on entry, which it always is here; the check decides.
ec-digest fix "$work/new.bin" 0 >/dev/null || true
ec-digest check "$work/new.bin" 0 || die "the patched region fails its digests"
ec-tables dump "$work/new.bin" 0 | grep -E "^ *(${TABLES//,/|}) " || die "no table lines in the dump of the build"

{ cmp -l "$work/pre.bin" "$work/new.bin" || true; } >"$work/diff.txt"
count=$(wc -l <"$work/diff.txt")
# A digest byte can keep its value by chance, so only the table bytes have an exact count.
table=$(awk -v d="$DIGEST" '$1 - 1 < d || $1 - 1 >= d + 32' "$work/diff.txt" | wc -l)
[ "$table" -eq $((ROWS * fields)) ] || die "$table bytes changed outside the payload digest, expected $((ROWS * fields))"
top=$(awk 'END { print $1 - 1 }' "$work/diff.txt")
[ "$top" -lt "$BANKS" ] || die "a changed byte at $top, inside the banks"
echo "== $count bytes changed ($table in the rows), highest at $(printf '%#x' "$top")"

echo "== rehearsal on flashrom's dummy chip"
cp "$dump" "$work/chip.bin"
dummy="dummy:emulate=W25Q128FV,image=$work/chip.bin"
flashrom -p "$dummy" -l "$layout" -i "ec:$work/new.bin" -w >"$work/fr1.txt" 2>&1 || {
  tail -5 "$work/fr1.txt"
  die "rehearsal write failed"
}
grep -q VERIFIED "$work/fr1.txt" || die "rehearsal write not verified"
outside=$({ cmp -l "$dump" "$work/chip.bin" || true; } | awk -v a="$REGION" -v s="$SIZE" '$1 - 1 < a || $1 - 1 >= a + s' | wc -l)
inside=$(ndiff "$dump" "$work/chip.bin")
{ [ "$outside" -eq 0 ] && [ "$inside" -eq "$count" ]; } || die "rehearsal: $inside bytes differ from the dump, $outside outside the EC region"
slice "$work/chip.bin" "$work/chip-ec.bin"
cmp -s "$work/chip-ec.bin" "$work/new.bin" || die "rehearsal: the chip's EC region is not the build"
echo "== write: VERIFIED, $inside bytes differ from the dump, $outside outside 0x700000-0x74FFFF"
flashrom -p "$dummy" -l "$layout" -i "ec:$work/pre.bin" -w >"$work/fr2.txt" 2>&1 || {
  tail -5 "$work/fr2.txt"
  die "rehearsal rollback failed"
}
grep -q VERIFIED "$work/fr2.txt" || die "rehearsal rollback not verified"
cmp -s "$dump" "$work/chip.bin" || die "rehearsal: the chip after the rollback is not the dump"
echo "== rollback: VERIFIED, chip equals the dump again"

emit() {
  cp "$1" "$2"
  chmod 444 "$2"
  (cd "${2%/*}" && sha256sum "${2##*/}" >"${2##*/}.sha256")
  cp -p "$2" "$2.sha256" "$fw/"
  [ "$(sha "$fw/${2##*/}")" = "$(sha "$2")" ] || die "$fw/${2##*/} differs from $2"
  echo "== $2 $(sha "$2"), copy in $fw: same sha256"
}
emit "$work/pre.bin" "$pre"
emit "$work/new.bin" "$new"
rm -rf "$work"

echo "== write (clip on, external 3.3 V on):"
echo "sudo --preserve-env=BOARD,WINTERMUTE_ROOT \"\$(command -v flash)\" --ec $new"
echo "== rollback, only if the board does not power on or the EC misbehaves:"
echo "sudo --preserve-env=BOARD,WINTERMUTE_ROOT \"\$(command -v flash)\" --ec $pre"
echo "ec-pl-build: OK n=$n changed=$count build=$(sha "$new" | cut -c1-16) rollback=$(sha "$pre" | cut -c1-16)"
