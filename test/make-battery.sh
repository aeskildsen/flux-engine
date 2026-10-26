#!/usr/bin/env bash
# Writes the SynthDefs of the test battery (test/web/battery.spec.mjs) into
# build/test/battery: one SynthDef for each UGen class in build/classes, made
# by test/make-battery-synthdefs.scd.
#
# sclang uses only its own class library and build/classes, not the
# SuperCollider extensions of the machine.
#
# Needs: scripts/prepare.py (it fills build/classes) and sclang on PATH
# (SuperCollider 3.14.1; the toolchain image has it).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/test/battery"
unset LD_LIBRARY_PATH

compgen -G "$root/build/classes/*.sc" > /dev/null \
	|| { echo "make-battery: no class files in build/classes (run scripts/prepare.py)" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out"

sc_prefix=$(dirname "$(dirname "$(readlink -f "$(command -v sclang)")")")
cat > "$out/sclang_conf.yaml" << EOF
includePaths:
    - "$sc_prefix/share/SuperCollider/SCClassLibrary"
    - "$root/build/classes"
excludePaths: []
postInlineWarnings: false
excludeDefaultPaths: true
EOF

# sclang does not stop by itself when the class library does not compile.
QT_QPA_PLATFORM=offscreen timeout 120 sclang -l "$out/sclang_conf.yaml" \
	"$root/test/make-battery-synthdefs.scd" "$root/build/classes" "$out" > "$out/sclang.log" 2>&1 \
	|| { tail -n 20 "$out/sclang.log"; exit 1; }
[ -f "$out/battery.json" ] || { echo "make-battery: sclang wrote no battery.json" >&2; tail -n 20 "$out/sclang.log"; exit 1; }
grep '^battery:' "$out/sclang.log"
