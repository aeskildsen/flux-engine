#!/usr/bin/env bash
# Prepares the SuperSonic submodule for a build with the flux-engine UGens:
#  1. Applies the patches in patches/ to the submodule (once; a second run
#     finds them applied and does nothing).
#  2. Generates the Faust UGen sources into build/generated.
#
# ISOSPIN_DIR is the folder with the Faust sources (default: the isospin
# submodule). Set it to use a local checkout instead.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
supersonic="$root/supersonic"
isospin=${ISOSPIN_DIR:-"$root/isospin"}
generated="$root/build/generated"

for patch in "$root"/patches/*.patch; do
	if git -C "$supersonic" apply --reverse --check "$patch" 2> /dev/null; then
		echo "prepare: already applied: $(basename "$patch")"
	else
		git -C "$supersonic" apply "$patch"
		echo "prepare: applied: $(basename "$patch")"
	fi
done

if [ ! -f "$isospin/woodbar.dsp" ]; then
	echo "prepare: no woodbar.dsp in $isospin (set ISOSPIN_DIR)" >&2
	exit 1
fi

# The Faust UGens. -cn must be the same name as the first argument of
# faust-static-ugen.py. -ftz 1 flushes denormals to zero, as the physmod
# playground does.
mkdir -p "$generated"
faust -a supercollider.cpp -cn Woodbar -ftz 1 -I "$isospin" \
	"$isospin/woodbar.dsp" -o "$generated/Woodbar-raw.cpp"
python3 -I "$root/scripts/faust-static-ugen.py" Woodbar \
	"$generated/Woodbar-raw.cpp" "$generated/Woodbar.cpp.new"
# Replace the source only when it changed, so that an unchanged UGen is not
# compiled again.
if cmp -s "$generated/Woodbar.cpp.new" "$generated/Woodbar.cpp"; then
	rm "$generated/Woodbar.cpp.new"
else
	mv "$generated/Woodbar.cpp.new" "$generated/Woodbar.cpp"
fi
echo "prepare: generated $generated/Woodbar.cpp ($(faust --version | head -n 1))"
