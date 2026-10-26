#!/usr/bin/env bash
# Builds the engine, runs all tests and makes the engine package: the steps of
# the release workflow (.github/workflows/release.yml). Runs in the toolchain
# image, in CI and locally:
#
#   scripts/in-image.sh scripts/ci.sh
#   scripts/in-image.sh scripts/ci.sh --release v0.91.0-flux.3
#
# With --release <tag> the script also checks that the tag is
# v<FLUX_ENGINE_VERSION> of engine-version.env and stops before it builds a
# development package: the isospin UGens must come from the release that
# ugens.toml names, and the working tree must have no changes.
#
# Use a clean checkout (git clone --recurse-submodules). The script does not
# clean build/.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

tag=
case "${1-}" in
	"") ;;
	--release)
		tag=${2:?ci: --release needs a tag}
		;;
	*)
		echo "ci: unknown option: $1" >&2
		exit 1
		;;
esac

step() { echo; echo "=== $* ($(date -u +%H:%M:%S))"; }

version=$(sed -n 's/^FLUX_ENGINE_VERSION=//p' engine-version.env)
step "flux-engine $version, commit $(git rev-parse HEAD)"
git submodule status
if [ -n "$tag" ]; then
	[ "$tag" = "v$version" ] \
		|| { echo "ci: the tag $tag is not v$version (engine-version.env)" >&2; exit 1; }
	[ -z "${ISOSPIN_DIR-}" ] && [ ! -e local.env ] \
		|| { echo "ci: ISOSPIN_DIR or local.env is set; a release takes isospin from ugens.toml" >&2; exit 1; }
fi

step "Unit tests of prepare.py"
python3 -m unittest discover -s test -p 'test_*.py'

step "Native build"
scripts/build-native.sh

step "Native reference test (woodbar against native scsynth)"
test/native-woodbar.sh

step "Web build"
scripts/build-web.sh

step "Web tests (SAB and postMessage mode)"
npm ci --no-audit --no-fund
test/make-battery.sh
# One worker: the CPU budget tests of the battery measure the engine's block
# rate, and other browsers that play at the same time would use the same CPUs.
npx playwright test -c test/web --reporter=list --workers=1

step "Package"
scripts/package.py
package="build/package/latest"
cat "$package/BUILDINFO"
if [ -n "$tag" ]; then
	grep -qx 'kind=release' "$package/BUILDINFO" \
		|| { echo "ci: the package is a development build; a release needs kind=release" >&2; exit 1; }
	grep -qx "version=$version" "$package/BUILDINFO" \
		|| { echo "ci: the package version is not $version" >&2; exit 1; }
fi
echo "wasm: $(stat -c %s "$package/dist/wasm/scsynth-nrt.wasm") bytes"

step "Done"
