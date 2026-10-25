# flux-engine

The [SuperSonic](https://github.com/samaaron/supersonic) engine (scsynth in the browser) with more UGens linked in, for [Flux](https://github.com/aeskildsen/flux).

SuperSonic links all UGens statically into the engine; it cannot load plugins at run time. This repository is an overlay: it keeps SuperSonic unchanged as a submodule, applies one small patch that lets a build add plugin sources, and builds the engine with its own UGens. The Faust UGens come as ready C++ sources from the releases of [isospin](https://github.com/aeskildsen/isospin); this repository runs no Faust.

## Layout

| Path | What it is |
|---|---|
| `supersonic/` | SuperSonic, a submodule pinned to a release tag |
| `patches/supersonic-extra-plugins.patch` | Adds the `SCSYNTH_EXTRA_PLUGINS` hook to SuperSonic's engine build |
| `ugens.toml` | The manifest: the UGens that the hook adds (today the isospin release, its version and SHA-256) |
| `scripts/prepare.py` | Applies the patches, puts the UGen sources into `build/` and generates the hook input from `ugens.toml` (`build/plugins/extra-plugins.cmake` and `.h`: sources, build settings and load calls) |
| `scripts/build-native.sh` | Builds the native server into `build/native` |
| `scripts/build-web.sh` | Builds the web engine (wasm, client, workers) into `build/web/dist` |
| `scripts/package.py`, `engine-version.env` | Makes the engine package for Flux from the web build, and its version |
| `Containerfile`, `scripts/in-image.sh` | The toolchain image, and a command to run the scripts in it |
| `test/` | Tests of `prepare.py` (`test/test_prepare.py`) and of the built engine (`test/web`: the web engine in Chromium) |

## UGens

| UGen | Source |
|---|---|
| `PhysWoodbar` | `woodbar.dsp` in [isospin](https://github.com/aeskildsen/isospin) |

## Add a UGen

Add an entry to `ugens.toml`. `scripts/prepare.py` generates the CMake source list, the declarations and the `<Name>_Load` calls from it; do not write UGen names into SuperSonic's files. A new isospin UGen needs no change here: release isospin and change the version and SHA-256 of the `[isospin]` entry.

The tests of `prepare.py` need no build, no network and no Faust:

```sh
python3 -m unittest discover -s test -p 'test_*.py'
```

## Build and test (native)

The toolchain is SuperSonic's (CMake, a C++ compiler, Rust, the audio development libraries) plus Python 3.11 or later. The first build downloads the isospin release into `build/downloads` and checks its SHA-256.

```sh
git submodule update --init --recursive
scripts/build-native.sh
test/native-woodbar.sh
```

`test/native-woodbar.sh` compares the headless SuperSonic with a render in native scsynth. It also needs sclang and scsynth 3.14.1 on `PATH` (the toolchain image has them from nixpkgs), and numpy for `python3` (else `uv`). It builds the isospin UGens as a plugin for native scsynth (`test/native-plugin`) and takes their classes from `build/isospin/classes`; it does not use the SuperCollider extensions of the machine. It also checks that the SynthDef that the class makes is the same as the fixture of the web tests (`test/assets/wb.scsyndef`).

The same in the toolchain image:

```sh
scripts/in-image.sh scripts/build-native.sh
scripts/in-image.sh test/native-woodbar.sh
```

## Build and test (web)

The web build needs the toolchain of SuperSonic's web build:

| Part | Version |
|---|---|
| Emscripten SDK | 4.0.21 |
| Rust | `nightly-2026-07-02` with `rust-src`, targets `wasm32-unknown-emscripten` and `wasm32-unknown-unknown`; stable 1.99.1 for the native build |
| wasm-bindgen-cli | 0.2.127 |
| Node.js | the one in the Emscripten SDK |
| Chromium (tests) | the one of `@playwright/test` 1.62.1 |

The `Containerfile` is the record of these versions. The scripts run the same in the toolchain image and on a host that has the toolchain (for example the `dev` box, with the Emscripten SDK in `~/emsdk`).

```sh
scripts/build-web.sh
npm ci
npx playwright install chromium
npx playwright test -c test/web
```

The web build took about 2 minutes on baldur (first build, empty caches). The tests play the woodbar test SynthDef (`test/assets/wb.scsyndef`, made by `test/make-synthdef.scd`) in two modes:

- **SAB**: the page is cross-origin isolated (COOP and COEP headers) and SuperSonic uses shared memory.
- **postMessage**: the page has no such headers, the same as GitHub Pages, and SuperSonic uses postMessage.

In both modes the tests read the output with `AnalyserNode`s on the engine's output node. In SAB mode they also check SuperSonic's audio capture.

The same in the toolchain image (needs `podman`):

```sh
scripts/in-image.sh scripts/build-web.sh
scripts/in-image.sh npm ci
scripts/in-image.sh npx playwright test -c test/web
```

The build folders of the image and of a host build are not compatible; use `--clean` when you change from one to the other.

**Reproducible output.** The web build and the package give the same bytes from the same commit, in the toolchain image and on a host with the same toolchain versions, from any checkout path. `scripts/build-web.sh` keeps the build paths out of the output: cargo's `trim-paths` for Rust, and `-ffile-prefix-map` for C and C++ (the paths become `/flux-engine/…`, `/emsdk/…` and `/rustc/<commit>/…`). CMake reads these flags only when it configures a new build folder, so `build-web.sh` stops when the build folder was configured without them; run it once with `--clean`. The native build does not remove the paths.

**Size of the engine:** `scsynth-nrt.wasm` is 1,627,500 bytes (1.6 MB; Release build, isospin 0.2.0, SuperSonic 0.91.0, 2026-10-24).

## Engine package

The engine package is what Flux takes from this repository: the web engine and the SuperCollider class files of the UGens.

```sh
scripts/build-web.sh
scripts/package.py
```

The result is in `build/package`:

| Path | What it is |
|---|---|
| `flux-engine-<version>/dist/` | The web engine: client, workers, `wasm/scsynth-nrt.wasm`. Give its URL to the SuperSonic client as `baseURL` and as `coreBaseURL`. |
| `flux-engine-<version>/classes/` | The class files of the UGens (from the isospin release), for the sclang class path |
| `flux-engine-<version>/BUILDINFO`, `LICENSE`, `NOTICE.md` | The kind of build and the source commits, the licence, and where the corresponding source is |
| `flux-engine-<version>/package.json` | The name and version, so that a package manager (Flux uses pnpm) can install the tarball from its release URL |
| `flux-engine-<version>.tgz`, `.tgz.sha256` | The same folder as a tarball (the same input gives the same bytes), and its SHA-256 |
| `latest` | A link to the last package folder |

The version is `<SuperSonic version>-flux.<n>`, from `engine-version.env`. A development build (isospin from `ISOSPIN_DIR`, or a working tree with changes) gets the suffix `-dev` and `kind=development` in `BUILDINFO`. Do not release it.

To use the package in Flux during development, set `FLUX_ENGINE_DIR` to the package folder when you start Flux's dev server (see Flux's README):

```sh
FLUX_ENGINE_DIR=~/gp/audio/flux-engine/build/package/latest pnpm dev
```

## Change a UGen locally

Set `ISOSPIN_DIR` to an isospin working copy, in the environment or in `local.env` (not in git):

```sh
echo 'ISOSPIN_DIR=$HOME/gp/audio/isospin' > local.env  # the environment has priority
scripts/build-native.sh
```

The build then makes the UGen sources from that working copy with isospin's `scripts/build-sc-static.py`, and compiles only the UGens that changed. This needs Faust and Python 3.11 or later. The build is a development build: the scripts print a warning, and `build/isospin/BUILDINFO` has `kind=development`. Do not release it. To ship a change, release isospin and change the `[isospin]` entry in `ugens.toml`.

## License

AGPL-3.0-or-later, the same as SuperSonic. See `LICENSE`. The isospin UGen sources have their own licence notice (`build/isospin/NOTICE.md`).
