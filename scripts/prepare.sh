#!/usr/bin/env bash
# Prepares the SuperSonic submodule for a build with the flux-engine UGens:
#  1. Applies the patches in patches/ to the submodule (once; a second run
#     finds them applied and does nothing).
#  2. Puts the static UGen sources of isospin into build/isospin.
#
# The UGen sources come from the isospin release in isospin-release.env. The
# tarball is downloaded once into build/downloads and checked against its
# SHA-256. This needs no Faust.
#
# For local development, set ISOSPIN_DIR to an isospin working copy. The
# sources are then made from it with its scripts/build-sc-static.py (this
# needs faust and python3), and the build is a development build: do not
# release it. local.env (not in git) can set ISOSPIN_DIR.
#
# For tests, ISOSPIN_VERSION, ISOSPIN_SHA256 and ISOSPIN_URL replace the
# release values (ISOSPIN_URL can be a file:// URL).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
supersonic="$root/supersonic"
out="$root/build/isospin"

[ -f "$root/local.env" ] && . "$root/local.env"
. "$root/isospin-release.env"

for patch in "$root"/patches/*.patch; do
	if git -C "$supersonic" apply --reverse --check "$patch" 2> /dev/null; then
		echo "prepare: already applied: $(basename "$patch")"
	else
		git -C "$supersonic" apply "$patch"
		echo "prepare: applied: $(basename "$patch")"
	fi
done

if [ -n "${ISOSPIN_DIR:-}" ]; then
	# build-sc-static.py writes only the files that changed, so that only the
	# changed UGens are compiled again.
	python3 -I "$ISOSPIN_DIR/scripts/build-sc-static.py" --out "$out"
	echo "prepare: WARNING: development build, isospin UGens from $ISOSPIN_DIR" >&2
	exit 0
fi

version=${ISOSPIN_VERSION:-$ISOSPIN_RELEASE_VERSION}
sha256=${ISOSPIN_SHA256:-$ISOSPIN_RELEASE_SHA256}
name="isospin-sc-static-$version.tar.gz"
url=${ISOSPIN_URL:-"https://github.com/aeskildsen/isospin/releases/download/v$version/$name"}
tarball="$root/build/downloads/$name"

if [ -z "$sha256" ]; then
	echo "prepare: isospin-release.env has no SHA-256 for isospin $version (set ISOSPIN_DIR to build from a working copy)" >&2
	exit 1
fi

if ! echo "$sha256  $tarball" | sha256sum --check --status 2> /dev/null; then
	mkdir -p "$(dirname "$tarball")"
	curl -fsSL -o "$tarball.part" "$url"
	if ! echo "$sha256  $tarball.part" | sha256sum --check --status; then
		echo "prepare: $url does not have the SHA-256 in isospin-release.env" >&2
		rm -f "$tarball.part"
		exit 1
	fi
	mv "$tarball.part" "$tarball"
	echo "prepare: downloaded $name"
fi

# Unpack only when the release changed, so that an unchanged build does not
# compile the UGens again. A development build removes the .sha256 stamp.
if [ "$(cat "$out/.sha256" 2> /dev/null)" != "$sha256" ]; then
	rm -rf "$out"
	mkdir -p "$out"
	tar -xzf "$tarball" -C "$out" --strip-components=1
	echo "$sha256" > "$out/.sha256"
	echo "prepare: unpacked $name"
fi
echo "prepare: isospin $version"
