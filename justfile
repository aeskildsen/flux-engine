# Requires just 1.23.0 or later.
# The release recipe below replaces the release recipe of just/tailor.just.
set allow-duplicate-recipes
import 'just/loader.just'

# List available recipes
default:
    @just --list

# Fast check: native build and native reference tests in the toolchain image
check:
    scripts/in-image.sh sh -c 'scripts/build-native.sh && test/native-woodbar.sh && test/native-superpos.sh'

# Create a local release tag with just release <version> (for example 0.97.0-flux.3)
release $VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    source engine-version.env
    if [ "${VERSION}" != "${FLUX_ENGINE_VERSION}" ]; then
        echo "Error: ${VERSION} is not the version in engine-version.env (${FLUX_ENGINE_VERSION})" >&2
        exit 1
    fi
    # prepare.py patches the submodules, so changed files in them do not count.
    if [ -n "$(git status --porcelain --ignore-submodules=dirty)" ]; then
        echo "Error: Working directory is not clean" >&2
        exit 1
    fi
    if git show-ref --tags --verify --quiet "refs/tags/v${VERSION}"; then
        echo "Error: Tag v${VERSION} already exists" >&2
        exit 1
    fi
    # A local clone can miss tags that a release made on GitHub.
    if [ -n "$(git ls-remote --tags origin "refs/tags/v${VERSION}")" ]; then
        echo "Error: Tag v${VERSION} already exists on origin" >&2
        exit 1
    fi
    git tag -a "v${VERSION}" -m "v${VERSION}"
    echo "Tag v${VERSION} created. Before you push it, run the Release workflow"
    echo "by hand on main to fill the image cache (README.md, Release). Then:"
    echo "  git push origin v${VERSION}"
