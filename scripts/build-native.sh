#!/usr/bin/env bash
# Builds the native SuperSonic server with the flux-engine UGens into
# build/native. Runs in the dev box or in the toolchain image.
#
# The cmake calls are the same as in SuperSonic's scripts/build-native.sh,
# with the build folder in this repository and SCSYNTH_EXTRA_PLUGINS set.
# Options: --debug, --clean.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/build/native"
build_type=Release
for arg in "$@"; do
	case $arg in
		--debug) build_type=Debug ;;
		--clean) rm -rf "$build" ;;
		*)
			echo "build-native: unknown option: $arg" >&2
			exit 1
			;;
	esac
done

# Nix library paths in LD_LIBRARY_PATH break programs built against Ubuntu's
# glibc. The Rust toolchain for clockwork is in ~/.cargo/bin.
unset LD_LIBRARY_PATH
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

"$root/scripts/prepare.sh"

cmake -B "$build" -G Ninja \
	-DCMAKE_BUILD_TYPE="$build_type" \
	-DBUILD_TESTS=OFF \
	-DSCSYNTH_EXTRA_PLUGINS="$root/plugins/extra-plugins.cmake" \
	"$root/supersonic"
cmake --build "$build" --config "$build_type"

echo "build-native: built $build/SuperSonic"
