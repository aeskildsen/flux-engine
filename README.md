# flux-engine

The [SuperSonic](https://github.com/samaaron/supersonic) engine (scsynth in the browser) with more UGens linked in, for [Flux](https://github.com/aeskildsen/flux).

SuperSonic links all UGens statically into the engine; it cannot load plugins at run time. This repository is an overlay: it keeps SuperSonic unchanged as a submodule, applies one small patch that lets a build add plugin sources, and builds the engine with its own UGens.

## Layout

| Path | What it is |
|---|---|
| `supersonic/` | SuperSonic, a submodule pinned to a release tag |
| `patches/supersonic-extra-plugins.patch` | Adds the `SCSYNTH_EXTRA_PLUGINS` hook to SuperSonic's engine build |
| `plugins/extra-plugins.cmake`, `plugins/extra-plugins.h` | The UGens that the hook adds: sources, build settings and load calls |
| `scripts/prepare.sh` | Applies the patches and generates the Faust UGen sources |
| `scripts/faust-static-ugen.py` | Turns Faust's SuperCollider output into a statically linked plugin |
| `scripts/build-native.sh` | Builds the native server into `build/native` |
| `vendor/faust/` | The Faust headers that the generated UGens include |
| `test/` | Tests of the built engine |

## UGens

| UGen | Source |
|---|---|
| `PhysWoodbar` | `woodbar.dsp` in [isospin](https://github.com/aeskildsen/isospin) |

## Build and test (native)

The toolchain is SuperSonic's (CMake, a C++ compiler, Rust, the audio development libraries) plus Faust 2.85.9.

```sh
git submodule update --init --recursive
scripts/build-native.sh
test/native-woodbar.sh
```

`ISOSPIN_DIR` points the build at another checkout of the Faust sources. `test/native-woodbar.sh` also needs sclang and scsynth with the `PhysWoodbar` class and plugin installed, and `uv`.

## License

AGPL-3.0-or-later, the same as SuperSonic. See `LICENSE`. The vendored Faust headers have their own license (`vendor/faust/README.md`).
