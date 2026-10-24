# flux-engine

The [SuperSonic](https://github.com/samaaron/supersonic) engine (scsynth in the browser) with more UGens linked in, for [Flux](https://github.com/aeskildsen/flux).

SuperSonic links all UGens statically into the engine; it cannot load plugins at run time. This repository is an overlay: it keeps SuperSonic unchanged as a submodule, applies one small patch that lets a build add plugin sources, and builds the engine with its own UGens. The Faust UGens come as ready C++ sources from the releases of [isospin](https://github.com/aeskildsen/isospin); this repository runs no Faust.

## Layout

| Path | What it is |
|---|---|
| `supersonic/` | SuperSonic, a submodule pinned to a release tag |
| `patches/supersonic-extra-plugins.patch` | Adds the `SCSYNTH_EXTRA_PLUGINS` hook to SuperSonic's engine build |
| `plugins/extra-plugins.cmake`, `plugins/extra-plugins.h` | The UGens that the hook adds: sources, build settings and load calls |
| `isospin-release.env` | The isospin release (version and SHA-256) that the UGen sources come from |
| `scripts/prepare.sh` | Applies the patches and puts the isospin UGen sources into `build/isospin` |
| `scripts/build-native.sh` | Builds the native server into `build/native` |
| `test/` | Tests of the built engine |

## UGens

| UGen | Source |
|---|---|
| `PhysWoodbar` | `woodbar.dsp` in [isospin](https://github.com/aeskildsen/isospin) |

## Build and test (native)

The toolchain is SuperSonic's (CMake, a C++ compiler, Rust, the audio development libraries) plus `curl`. The first build downloads the isospin release into `build/downloads` and checks its SHA-256.

```sh
git submodule update --init --recursive
scripts/build-native.sh
test/native-woodbar.sh
```

`test/native-woodbar.sh` also needs sclang and scsynth with the `PhysWoodbar` class and plugin installed, and `uv`.

## Change a UGen locally

Set `ISOSPIN_DIR` to an isospin working copy, in the environment or in `local.env` (not in git):

```sh
echo 'ISOSPIN_DIR=$HOME/gp/audio/isospin' > local.env
scripts/build-native.sh
```

The build then makes the UGen sources from that working copy with isospin's `scripts/build-sc-static.py`, and compiles only the UGens that changed. This needs Faust and Python 3.11 or later. The build is a development build: the scripts print a warning, and `build/isospin/BUILDINFO` has `kind=development`. Do not release it. To ship a change, release isospin and change `isospin-release.env`.

## License

AGPL-3.0-or-later, the same as SuperSonic. See `LICENSE`. The isospin UGen sources have their own licence notice (`build/isospin/NOTICE.md`).
