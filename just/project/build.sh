#!/usr/bin/env bash
# Native and web build in the toolchain image.
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/in-image.sh scripts/build-native.sh
scripts/in-image.sh scripts/build-web.sh
