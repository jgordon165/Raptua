#!/bin/sh
# Builds the SNES ROM with PVSnesLib.
#
#   snes/build.sh <work dir> [--data <folder with FILE0000.GLB and FILE0001.GLB>]
#
# Needs PVSNESLIB_HOME (snes/setup-pvsneslib.sh fetches it), Python 3 and
# Pillow. The ROM lands in <work dir>/raptua-snes.sfc.
#
# Without --data the wave is Raptua's own (tools/snes_art.py draws it): no
# game content, so that ROM can be shared. With --data it is sector 1 wave 1
# converted from your own Raptor v1.2 files: that ROM is for you only, don't
# share it.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
out=${1:?usage: build.sh <work dir> [--data <folder with the GLB files>]}
shift
data=""
if [ "${1:-}" = "--data" ]; then data=${2:?--data needs a folder}; fi
: "${PVSNESLIB_HOME:?set PVSNESLIB_HOME to your PVSnesLib folder}"

rm -rf "$out"
mkdir -p "$out"
out=$(cd "$out" && pwd)
cp "$here"/src/*.c "$out/"
cp "$here/data.asm" "$out/"
cp "$here/Makefile.in" "$out/Makefile"
if [ -n "$data" ]; then
    python3 -I "$root/tools/snes_art.py" --out "$out" --data "$data"
else
    python3 -I "$root/tools/snes_art.py" --out "$out"
fi
cd "$out"
make
cp raptua.sfc raptua-snes.sfc
echo "ROM: $out/raptua-snes.sfc ($(wc -c < raptua-snes.sfc) bytes)"
