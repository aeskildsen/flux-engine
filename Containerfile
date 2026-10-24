# The flux-engine toolchain image: everything that scripts/build-native.sh,
# scripts/build-web.sh and the web tests (test/web) need. This file is the
# record of the toolchain versions. The dev box (Ubuntu 24.04) has the same
# versions; the image is the reference.
#
# Build and use it with scripts/in-image.sh (podman). The image has no
# Faust: the UGen sources come from the isospin release. It has no
# SuperCollider either, so test/native-woodbar.sh does not run in it.

# Ubuntu 24.04 (noble), amd64, pinned by digest.
FROM docker.io/library/ubuntu:24.04@sha256:a2d43bffc46670d7108bb3c0468c67c5557c4c92e83e1e34cbff1322ad1b94dc

ARG DEBIAN_FRONTEND=noninteractive

# Native build: the C++ toolchain, CMake (SuperSonic needs 3.24 or later) and
# the audio development libraries. git applies the patches, curl downloads
# the isospin release. python3 and xz-utils are for emsdk.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build pkg-config \
      libasound2-dev libudev-dev libjack-jackd2-dev libpipewire-0.3-dev \
      git curl ca-certificates python3 xz-utils bzip2 \
 && rm -rf /var/lib/apt/lists/*

# Emscripten SDK 4.0.21 (the version in SuperSonic's Dockerfile). emsdk also
# installs its own Node.js; the image uses it for the JavaScript bundle and
# the tests.
ENV EMSDK=/opt/emsdk
RUN git clone https://github.com/emscripten-core/emsdk.git "$EMSDK" \
 && git -C "$EMSDK" checkout --quiet b2436aafa7351ee1b581f15841f1b45ed716a279 \
 && "$EMSDK/emsdk" install 4.0.21 \
 && "$EMSDK/emsdk" activate 4.0.21 \
 && ln -s "$(ls -d "$EMSDK"/node/*/bin)" "$EMSDK/node/bin" \
 && rm -rf "$EMSDK/downloads"
ENV PATH=$EMSDK:$EMSDK/upstream/emscripten:$EMSDK/node/bin:$PATH

# Rust for clockwork: a stable toolchain for the native build; for the web
# build the nightly with rust-src (std is built again with atomics for the
# shared heap), the two wasm targets, and wasm-bindgen-cli at the version
# that clockwork/rust/Cargo.lock pins.
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
ENV PATH=$CARGO_HOME/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain 1.99.1 \
 && rustup toolchain install nightly-2026-07-02 --profile minimal \
      --component rust-src \
      --target wasm32-unknown-emscripten --target wasm32-unknown-unknown \
 && cargo install wasm-bindgen-cli --version 0.2.127 --locked \
 && rm -rf "$CARGO_HOME/registry"

# Chromium for the web tests, at the version that @playwright/test 1.62.1
# (package.json) expects, with its system libraries.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npx --yes playwright@1.62.1 install --with-deps chromium \
 && rm -rf /var/lib/apt/lists/* /root/.npm

WORKDIR /work
