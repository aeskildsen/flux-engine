#!/usr/bin/env bash
# Runs the full CI job (scripts/ci.sh) in the toolchain image, from the host.
# The image is the only environment for flux-engine; see README.md.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec scripts/in-image.sh scripts/ci.sh "$@"
