#!/usr/bin/env bash
# Builds the web engine (scsynth-nrt.wasm, the client and the workers) with
# the flux-engine UGens into build/web/dist. Runs in the dev box or in the
# toolchain image.
#
# SuperSonic's own scripts/build-web.sh does the build. It reads the hook from
# the SCSYNTH_EXTRA_PLUGINS environment variable, so the script needs no
# change. It writes into the submodule (build/web and dist/, both ignored
# there); this script then copies dist/ into build/web/dist.
# Options: --debug, --release (passed to SuperSonic's script), --clean.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
supersonic="$root/supersonic"
out="$root/build/web"
args=()
for arg in "$@"; do
	case $arg in
		--debug | --release) args+=("$arg") ;;
		--clean) rm -rf "$out" "$supersonic/build/web" "$supersonic/dist" ;;
		*)
			echo "build-web: unknown option: $arg" >&2
			exit 1
			;;
	esac
done

# Nix library paths in LD_LIBRARY_PATH break programs built against Ubuntu's
# glibc. The Rust toolchain for clockwork is in ~/.cargo/bin. Emscripten comes
# from EMSDK, or from ~/emsdk when emcc is not on PATH.
unset LD_LIBRARY_PATH
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v emcc > /dev/null; then
	emsdk=${EMSDK:-$HOME/emsdk}
	# shellcheck source=/dev/null
	EMSDK_QUIET=1 . "$emsdk/emsdk_env.sh"
fi

"$root/scripts/prepare.sh"

# Reproducible output: the build must not write the paths of this checkout or
# of the toolchain into the wasm, so that the same sources give the same bytes
# in the toolchain image and on a host.
#  - Rust: cargo's trim-paths profile setting maps the standard library
#    sources to /rustc/<commit>, the workspace to relative paths and the
#    dependencies to <name>-<version>. It is unstable in the pinned nightly
#    (stable from Rust 1.101), so the [unstable] key enables it; both keys are
#    set as cargo config environment variables. A RUSTFLAGS
#    --remap-path-prefix does not work here: clockwork sets its own RUSTFLAGS
#    for the wasm target, and cargo uses only one source of flags.
#    https://doc.rust-lang.org/nightly/cargo/reference/unstable.html#profile-trim-paths-option
#    https://doc.rust-lang.org/nightly/cargo/reference/config.html#environment-variables
#  - C and C++: -ffile-prefix-map remaps paths in __FILE__, __builtin_FILE()
#    and debug information. CMake reads CFLAGS and CXXFLAGS only when it
#    configures a new build folder, so an older folder needs --clean.
#    https://clang.llvm.org/docs/ClangCommandLineReference.html
#    https://cmake.org/cmake/help/v3.28/envvar/CXXFLAGS.html
export CARGO_UNSTABLE_TRIM_PATHS=true
export CARGO_PROFILE_RELEASE_TRIM_PATHS=object
emsdk_root=$(cd "$(dirname "$(command -v emcc)")/../.." && pwd)
prefix_map="-ffile-prefix-map=$root=/flux-engine -ffile-prefix-map=$emsdk_root=/emsdk"
export CFLAGS="${CFLAGS:+$CFLAGS }$prefix_map"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }$prefix_map"
cache="$supersonic/build/web/CMakeCache.txt"
if [ -f "$cache" ] && ! grep -qF -- "-ffile-prefix-map=$root=/flux-engine" "$cache"; then
	echo "build-web: $supersonic/build/web was configured without the path maps (or from another path); run with --clean" >&2
	exit 1
fi

# SuperSonic's build bundles the JavaScript with the esbuild in its
# node_modules (versions from its package-lock.json).
if [ ! -x "$supersonic/node_modules/.bin/esbuild" ]; then
	(cd "$supersonic" && npm ci --no-audit --no-fund)
fi

# esbuild writes the source paths into the bundles relative to the working
# folder, so the build always runs from the repository root.
cd "$root"
SCSYNTH_EXTRA_PLUGINS="$root/plugins/extra-plugins.cmake" \
	"$supersonic/scripts/build-web.sh" "${args[@]}"

rm -rf "$out/dist"
mkdir -p "$out"
cp -r "$supersonic/dist" "$out/dist"

echo "build-web: built $out/dist/wasm/scsynth-nrt.wasm ($(stat -c %s "$out/dist/wasm/scsynth-nrt.wasm") bytes)"
if grep -qx 'kind=development' "$root/build/isospin/BUILDINFO"; then
	echo "build-web: WARNING: development build (isospin UGens from a working copy); do not release it" >&2
fi
