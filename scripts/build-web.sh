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

# SuperSonic's build bundles the JavaScript with the esbuild in its
# node_modules (versions from its package-lock.json).
if [ ! -x "$supersonic/node_modules/.bin/esbuild" ]; then
	(cd "$supersonic" && npm ci --no-audit --no-fund)
fi

SCSYNTH_EXTRA_PLUGINS="$root/plugins/extra-plugins.cmake" \
	"$supersonic/scripts/build-web.sh" "${args[@]}"

rm -rf "$out/dist"
mkdir -p "$out"
cp -r "$supersonic/dist" "$out/dist"

echo "build-web: built $out/dist/wasm/scsynth-nrt.wasm ($(stat -c %s "$out/dist/wasm/scsynth-nrt.wasm") bytes)"
if grep -qx 'kind=development' "$root/build/isospin/BUILDINFO"; then
	echo "build-web: WARNING: development build (isospin UGens from a working copy); do not release it" >&2
fi
