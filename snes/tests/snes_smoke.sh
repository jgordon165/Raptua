#!/bin/sh
# Smoke test for the SNES ROM: runs it headless in the snes9x libretro core
# with no input, so the ship flies itself and fires, and fails unless the
# map scrolled, enemies appeared and some were shot down (read from work RAM).
#
#   snes/tests/snes_smoke.sh <rom> <symbols (.sym)> <out dir>
#
# Needs the core: apt install libretro-snes9x (or set SNES9X_CORE).
set -eu
rom=$1 sym=$2 out=$3
here=$(cd "$(dirname "$0")" && pwd)
core=${SNES9X_CORE:-/usr/lib/x86_64-linux-gnu/libretro/snes9x_libretro.so}
game=$(awk '$2=="game"{print substr($1,3,2)":"substr($1,5)}' "$sym")
[ -n "$game" ] || { echo "no 'game' symbol in $sym"; exit 1; }
python3 -I "$here/libretro_run.py" "$core" "$rom" "$out" --frames 4000 --snaps 300,2000,3900 --game "$game"
val() { sed -n "s/.* $1=\(-*[0-9]*\).*/\1/p; s/^$1=\(-*[0-9]*\).*/\1/p" "$out/result.txt" | head -1; }
cam=$(val cam); spawned=$(val spawned); kills=$(val kills)
echo "cam=$cam spawned=$spawned kills=$kills"
if [ "${cam:-9999}" -gt 4300 ] || [ "${spawned:-0}" -lt 5 ] || [ "${kills:-0}" -lt 2 ]; then
    echo "smoke test failed: the map should have scrolled, enemies appeared and some been shot down"
    exit 1
fi
echo "smoke test passed"
