#!/usr/bin/env bash
# Runs a command in the toolchain image (Containerfile) with podman. Builds
# the image first; podman uses its layer cache, so this is fast when the
# Containerfile did not change.
#
#   scripts/in-image.sh scripts/build-web.sh
#   scripts/in-image.sh npx playwright test -c test/web
#
# The repository is mounted at the same path as on the host, so build paths
# are the same in and out of the image. The build folders of the dev box and
# of the image are not compatible (other compiler and Emscripten paths): use
# --clean on the build scripts when you change from one to the other.
#
# The Emscripten and npm caches are in the podman volume flux-engine-cache and
# the Cargo registry in flux-engine-cargo-registry, so that a second run does
# not fetch and build them again.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
image=localhost/flux-engine-toolchain

# The image copies no files, so the build context is an empty folder.
context=$(mktemp -d)
status=0
podman build --quiet --tag "$image" --file "$root/Containerfile" "$context" > /dev/null || status=$?
rmdir "$context"
[ "$status" -eq 0 ] || exit "$status"

tty=()
[ -t 0 ] && [ -t 1 ] && tty=(--interactive --tty)
exec podman run --rm "${tty[@]}" \
	--volume "$root:$root:z" \
	--volume flux-engine-cache:/cache \
	--env EM_CACHE=/cache/emscripten \
	--volume flux-engine-cargo-registry:/usr/local/cargo/registry \
	--env npm_config_cache=/cache/npm \
	--workdir "$root" \
	"$image" "$@"
