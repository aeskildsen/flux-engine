#!/usr/bin/env bash
# Native woodbar test. Plays the woodbar test note in headless SuperSonic
# (build/native/SuperSonic) and compares the recording with a render in native
# scsynth.
#
# The UGen class and the native plugin come from the isospin UGens of the
# build (build/isospin): the class from its classes/ folder, the plugin built
# by test/native-plugin. sclang and scsynth use only these and their own class
# library and plugins, not the SuperCollider extensions of the machine.
#
# Needs: a native build (scripts/build-native.sh), sclang and scsynth on PATH
# (SuperCollider 3.14.1), and numpy for python3 (else uv). Writes its files to
# build/test/native-woodbar.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
here="$root/test"
out="$root/build/test/native-woodbar"
server="$root/build/native/SuperSonic"
unset LD_LIBRARY_PATH

[ -x "$server" ] || { echo "native-woodbar: no $server (run scripts/build-native.sh)" >&2; exit 1; }
[ -f "$root/build/isospin/isospin.cmake" ] || { echo "native-woodbar: no build/isospin (run scripts/prepare.py)" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"

# The SuperCollider installation of the scsynth on PATH: <prefix>/bin/scsynth.
sc_prefix=$(dirname "$(dirname "$(readlink -f "$(command -v scsynth)")")")
echo "== $(scsynth -v | head -n 1) at $sc_prefix"

echo "== Native plugin"
cmake -S "$here/native-plugin" -B "$root/build/test/native-plugin" -G Ninja \
	-DSC_INCLUDE_DIR="$sc_prefix/include/SuperCollider" > "$out/native-plugin.log"
cmake --build "$root/build/test/native-plugin" >> "$out/native-plugin.log" \
	|| { tail -n 20 "$out/native-plugin.log"; exit 1; }

# The class library of sclang and the isospin classes only. With
# excludeDefaultPaths sclang also leaves out its class library, so it is in
# includePaths.
cat > "$out/sclang_conf.yaml" << EOF
includePaths:
    - "$sc_prefix/share/SuperCollider/SCClassLibrary"
    - "$root/build/isospin/classes"
excludePaths: []
postInlineWarnings: false
excludeDefaultPaths: true
EOF
sclang() { QT_QPA_PLATFORM=offscreen command sclang -l "$out/sclang_conf.yaml" "$@"; }

echo "== SynthDef"
sclang "$here/make-synthdef.scd" "$out" > "$out/make-synthdef.log" 2>&1 \
	|| { tail -n 20 "$out/make-synthdef.log"; exit 1; }
[ -f "$out/wb.scsyndef" ] || { echo "native-woodbar: sclang wrote no wb.scsyndef" >&2; tail -n 20 "$out/make-synthdef.log"; exit 1; }
# The web tests use the fixture; it must be the SynthDef that the class makes.
if ! cmp -s "$out/wb.scsyndef" "$here/assets/wb.scsyndef"; then
	echo "native-woodbar: wb.scsyndef differs from test/assets/wb.scsyndef (make the fixture again with test/make-synthdef.scd)" >&2
	exit 1
fi
echo "OK: wb.scsyndef is the same as test/assets/wb.scsyndef"

echo "== Headless SuperSonic"
python3 "$here/native-headless-test.py" "$server" "$out/wb.scsyndef" "$out/supersonic.wav"

echo "== Native scsynth reference"
# The plugins of scsynth and the isospin plugin only (scsynth -U).
UGEN_PLUGINS_PATH="$sc_prefix/lib/SuperCollider/plugins:$root/build/test/native-plugin" \
	sclang "$here/native-reference-render.scd" "$out" > "$out/reference.log" 2>&1 \
	|| { tail -n 20 "$out/reference.log"; exit 1; }
[ -f "$out/nrt.wav" ] || { echo "native-woodbar: no reference render" >&2; tail -n 20 "$out/reference.log"; exit 1; }

echo "== Compare"
cd "$here"
if python3 -c 'import numpy' 2> /dev/null; then
	python3 compare-renders.py "$out/supersonic.wav" "$out/nrt.wav"
else
	uv run --quiet --no-project --managed-python --python 3.12 --with numpy python compare-renders.py "$out/supersonic.wav" "$out/nrt.wav"
fi
