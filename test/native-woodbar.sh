#!/usr/bin/env bash
# Native woodbar test. Plays the woodbar test note in headless SuperSonic
# (build/native/SuperSonic) and compares the recording with a render in native
# scsynth with the installed PhysWoodbar plugin.
#
# Needs: a native build (scripts/build-native.sh), sclang and scsynth, the
# PhysWoodbar class and plugin in the SuperCollider extensions, and uv (for
# numpy). Writes its files to build/test/native-woodbar.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
here="$root/test"
out="$root/build/test/native-woodbar"
server="$root/build/native/SuperSonic"
unset LD_LIBRARY_PATH

[ -x "$server" ] || { echo "native-woodbar: no $server (run scripts/build-native.sh)" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"

echo "== SynthDef"
QT_QPA_PLATFORM=offscreen sclang "$here/make-synthdef.scd" "$out" > "$out/make-synthdef.log" 2>&1 \
	|| { tail -n 20 "$out/make-synthdef.log"; exit 1; }
[ -f "$out/wb.scsyndef" ] || { echo "native-woodbar: sclang wrote no wb.scsyndef" >&2; tail -n 20 "$out/make-synthdef.log"; exit 1; }

echo "== Headless SuperSonic"
python3 "$here/native-headless-test.py" "$server" "$out/wb.scsyndef" "$out/supersonic.wav"

echo "== Native scsynth reference"
QT_QPA_PLATFORM=offscreen sclang "$here/native-reference-render.scd" "$out" > "$out/reference.log" 2>&1 \
	|| { tail -n 20 "$out/reference.log"; exit 1; }
[ -f "$out/nrt.wav" ] || { echo "native-woodbar: no reference render" >&2; tail -n 20 "$out/reference.log"; exit 1; }

echo "== Compare"
cd "$here"
uv run --quiet --no-project --managed-python --python 3.12 --with numpy python compare-renders.py "$out/supersonic.wav" "$out/nrt.wav"
