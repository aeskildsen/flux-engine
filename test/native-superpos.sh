#!/usr/bin/env bash
# Native SuperPos test. Plays the SuperPos test cloud in headless SuperSonic
# (build/native/SuperSonic) and renders it in native scsynth, with SuperPos and
# with the same cloud made of Impulse, Phasor and GrainBuf. Then it compares
# the three (compare-superpos.py).
#
# The SuperPos class and the native plugin come from the isospin UGens of the
# build (build/isospin), as in native-woodbar.sh. sclang and scsynth use only
# these and their own class library and plugins.
#
# Needs: a native build (scripts/build-native.sh), sclang and scsynth on PATH
# (SuperCollider 3.14.1), and numpy for python3 (else uv). Writes its files to
# build/test/native-superpos.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
here="$root/test"
out="$root/build/test/native-superpos"
server="$root/build/native/SuperSonic"
unset LD_LIBRARY_PATH

[ -x "$server" ] || { echo "native-superpos: no $server (run scripts/build-native.sh)" >&2; exit 1; }
[ -f "$root/build/isospin/isospin.cmake" ] || { echo "native-superpos: no build/isospin (run scripts/prepare.py)" >&2; exit 1; }
[ -f "$root/build/isospin/classes/SuperPos.sc" ] || { echo "native-superpos: the isospin UGens have no SuperPos" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"

sc_prefix=$(dirname "$(dirname "$(readlink -f "$(command -v scsynth)")")")
echo "== $(scsynth -v | head -n 1) at $sc_prefix"

echo "== Native plugin"
cmake -S "$here/native-plugin" -B "$root/build/test/native-plugin" -G Ninja \
	-DSC_INCLUDE_DIR="$sc_prefix/include/SuperCollider" > "$out/native-plugin.log"
cmake --build "$root/build/test/native-plugin" >> "$out/native-plugin.log" \
	|| { tail -n 20 "$out/native-plugin.log"; exit 1; }

# The class library of sclang and the isospin classes only.
cat > "$out/sclang_conf.yaml" << CONF
includePaths:
    - "$sc_prefix/share/SuperCollider/SCClassLibrary"
    - "$root/build/isospin/classes"
excludePaths: []
postInlineWarnings: false
excludeDefaultPaths: true
CONF
# sclang does not stop by itself when the class library does not compile.
sclang_bin=$(command -v sclang)
sclang() { QT_QPA_PLATFORM=offscreen timeout 120 "$sclang_bin" -l "$out/sclang_conf.yaml" "$@"; }

echo "== SynthDefs"
sclang "$here/make-superpos-synthdefs.scd" "$out" > "$out/make-synthdefs.log" 2>&1 \
	|| { tail -n 20 "$out/make-synthdefs.log"; exit 1; }
[ -f "$out/sp.scsyndef" ] || { echo "native-superpos: sclang wrote no sp.scsyndef" >&2; tail -n 20 "$out/make-synthdefs.log"; exit 1; }
# The web tests use the fixtures; they must be the SynthDefs that the classes
# make.
for def in sp sp_live; do
	if ! cmp -s "$out/$def.scsyndef" "$here/assets/$def.scsyndef"; then
		echo "native-superpos: $def.scsyndef differs from test/assets/$def.scsyndef (copy $out/$def.scsyndef there)" >&2
		exit 1
	fi
	echo "OK: $def.scsyndef is the same as test/assets/$def.scsyndef"
done

echo "== Headless SuperSonic"
python3 "$here/native-superpos-headless.py" "$server" "$out/sp.scsyndef" "$out/supersonic.wav" > "$out/headless.log" 2>&1 \
	|| { tail -n 20 "$out/headless.log"; exit 1; }
tail -n 1 "$out/headless.log"

echo "== Native scsynth renders"
UGEN_PLUGINS_PATH="$sc_prefix/lib/SuperCollider/plugins:$root/build/test/native-plugin" \
	sclang "$here/native-superpos-render.scd" "$out" > "$out/render.log" 2>&1 \
	|| { tail -n 20 "$out/render.log"; exit 1; }
for f in sp sp_grainbuf sp_live_open sp_live_frozen; do
	[ -f "$out/$f.wav" ] || { echo "native-superpos: no $f.wav" >&2; tail -n 20 "$out/render.log"; exit 1; }
done

echo "== Compare"
cd "$here"
if python3 -c 'import numpy' 2> /dev/null; then
	py() { python3 "$@"; }
else
	py() { uv run --quiet --no-project --managed-python --python 3.12 --with numpy python "$@"; }
fi
py compare-superpos.py "$out/sp.wav" "$out/sp_grainbuf.wav" "$out/supersonic.wav"
py compare-superpos-live.py "$out/sp_live_open.wav" "$out/sp_live_frozen.wav"
