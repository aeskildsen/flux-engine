#!/usr/bin/env bash
# Runs a command in the toolchain image (Containerfile) with podman. Builds
# the image first; podman uses its layer cache, so this is fast when the
# Containerfile did not change.
#
#   scripts/in-image.sh scripts/build-web.sh
#   scripts/in-image.sh npx playwright test -c test/web
#
# The repository is mounted at the same path as on the host, so build paths
# are the same in and out of the image. The build folders of a host toolchain
# and of the image are not compatible (other compiler and Emscripten paths):
# use --clean on the build scripts when you change from one to the other.
#
# The Emscripten and npm caches are in the podman volume flux-engine-cache and
# the Cargo registry in flux-engine-cargo-registry, so that a second run does
# not fetch and build them again.
#
# ISOSPIN_DIR (from the environment, else from local.env, as in
# scripts/prepare.py): the isospin working copy is mounted read-only at the
# same path, and ISOSPIN_DIR is given to the container as an absolute path.
# A leading ~ must be expanded here, because HOME in the image is /root.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
image=localhost/flux-engine-toolchain

isospin=()
isospin_dir=${ISOSPIN_DIR-}
if [ -z "${ISOSPIN_DIR+x}" ] && [ -f "$root/local.env" ]; then
	# Use the parser of prepare.py, so that both read local.env the same way.
	isospin_dir=$(python3 -I - "$root" <<-'EOF'
		import os, sys
		from pathlib import Path
		sys.path.insert(0, str(Path(sys.argv[1]) / "scripts"))
		import prepare
		env = prepare.read_env(Path(sys.argv[1]) / "local.env", dict(os.environ))
		print(env.get("ISOSPIN_DIR", ""))
	EOF
	)
fi
if [ -n "$isospin_dir" ]; then
	isospin_dir=$(cd "${isospin_dir/#\~/$HOME}" && pwd)
	isospin=(--volume "$isospin_dir:$isospin_dir:ro,z" --env "ISOSPIN_DIR=$isospin_dir")
fi

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
	"${isospin[@]}" \
	--workdir "$root" \
	"$image" "$@"
