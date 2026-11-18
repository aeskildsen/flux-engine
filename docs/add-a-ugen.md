# How a UGen gets into Flux

This guide follows one third-party UGen, `MiPlaits` from [mi-UGens](https://github.com/v7b1/mi-UGens), from its source files to a note in [Flux](https://github.com/aeskildsen/flux). Each step names the file that does the work. At the end there is a checklist for the next UGen.

UGens from [isospin](https://github.com/aeskildsen/isospin) (Faust instruments and hand-written C++ such as `SuperPos`) take a shorter path: isospin releases the C++ sources and the class files, and this repository downloads that release. See [isospin UGens](#isospin-ugens).

## Why the path is long

SuperSonic links all UGens into one engine binary. It cannot load a plugin at run time. Thus a new UGen needs a new engine build, and Flux needs a new engine release.

## 1. The source: a pinned submodule

- `mi-UGens` is a git submodule of this repository, pinned to one commit.
- The submodule keeps the relation to the original repository, so you can see each upstream change and its history.
- `mi-UGens` has its own copy of the Mutable Instruments code (`eurorack/`). `MiPlaits` builds against that copy, so this repository needs no other submodule.

## 2. The manifest: `ugens.toml`

`ugens.toml` lists each UGen that the engine adds. The `MiPlaits` entry (`[[sources]]`) gives:

- the submodule (`root = "mi-UGens"`);
- the source files, as glob patterns relative to `root`;
- the include folders and the compile definitions (`TEST`: portable C++, not ARM assembly);
- the load function (`MiPlaits_Load`);
- the class file (`sc/Classes/MiPlaits.sc`);
- the patches;
- the licence notice for the package.

Add a third-party UGen only in this file. Do not write UGen names into the SuperSonic files.

## 3. The patches: `patches/mi-UGens/`

The submodule stays unchanged in git. `scripts/prepare.py` applies the patches to the working tree before each build. A second run finds them applied and does nothing. `MiPlaits` has two patches:

- `miplaits-rt-alloc.patch`: scsynth runs the constructor of a UGen on the audio thread. There, a UGen must not use the heap (`new`, `malloc`). The original constructor used `new` for the Plaits voice. The patch makes it use `RTAlloc`, which takes memory from the real-time pool. Each Plaits node takes about 43 KB of the pool (8 MB by default).
- `miplaits-plural-guest.patch`: since SuperSonic v0.95.0, one process can have more than one engine (World). The interface table that `PluginLoad` gets (`inTable`) belongs to one World and goes away with it. The original code kept `inTable` in `ft`. The patch makes `ft` point to the constant `gInterfaceTable`. All 12 `mi-UGens` projects have the same `static InterfaceTable *ft`, so each one needs this change.

## 4. The preparation: `scripts/prepare.py`

Each build runs this script first. It does these steps in sequence:

1. It applies the hook patch to the SuperSonic submodule, and the patches of each manifest entry to their submodules.
2. It gets the isospin UGens: it downloads the pinned release, or it uses a working copy (`ISOSPIN_DIR`).
3. It expands the glob patterns into a sorted list of files. If a pattern finds no file, the script stops.
4. It writes the hook input into `build/plugins/` (see step 5).
5. It copies all class files into `build/classes/`.

The script writes a file only when its content changes. Thus a build with no change compiles nothing again.

## 5. The hook input: `build/plugins/`

The script generates two files:

- `extra-plugins.cmake` gives the list of source files and their build settings to CMake. The build settings apply only to these files, so they do not change the SuperSonic sources.
- `extra-plugins.h` declares `MiPlaits_Load()` and calls it in the function `SC_ExtraPlugins_Load()`. The declaration uses C++ linkage, because `PluginLoad()` gives C++ linkage under SuperSonic's `STATIC_PLUGINS`. Set `linkage = "c"` in the entry for a UGen with C linkage.

If two entries name the same source file (for example the shared `stmlib` files), the script builds that file once. If the two entries give different build settings for that file, the script stops.

## 6. The hook: `patches/supersonic-extra-plugins.patch`

- The hook patch adds one CMake variable, `SCSYNTH_EXTRA_PLUGINS`. CMake reads the file that this variable names (step 5) and adds those sources to the engine.
- `SC_Lib_Cintf.cpp` calls `SC_ExtraPlugins_Load()` after the built-in UGens. This registers `MiPlaits` in the engine.

## 7. The build

Run the build scripts in the toolchain image with `scripts/in-image.sh` (see the README).

- `scripts/build-native.sh` builds the native server. Use it for fast tests.
- `scripts/build-web.sh` builds the wasm engine. Flux uses this engine.
- The web build removes local paths from the output (`-ffile-prefix-map`), so two builds of the same sources give the same bytes.

## 8. The package: `scripts/package.py`

- The package holds the web engine (`dist/`) and the class files (`classes/`).
- `BUILDINFO` gives the kind of build, the version and the source commits.
- `NOTICE.md` gives the licence of each third-party UGen. `MiPlaits` is GPL-3.0-or-later; the Plaits and stmlib code is MIT.
- Do not make a release package on your machine. A release comes from CI (see "Release" in the README).

## 9. Flux: `synthdefs/plaits.scd`

- Flux compiles its SynthDefs with the class files of the package. sclang needs the `MiPlaits` class; it does not need the UGen itself.
- `MiPlaits` takes a MIDI note. The SynthDef converts the `freq` from Flux with `cpsmidi`. Thus Flux keeps its rule: a tonal SynthDef takes `freq` in Hz.
- The SynthDef finds the class by name (`\MiPlaits.asClass`). If the class is missing, the file makes no SynthDef, and the other SynthDefs still compile.
- To use the new engine, change the `flux-engine` URL in Flux's `package.json` to the new release and run `pnpm install`. To try a local build first, set `FLUX_ENGINE_DIR` (see Flux's `DEVELOPING.md`).

## The tests at each step

| Step | Test |
|---|---|
| Manifest and generator | `test/test_prepare.py`. It needs no build and no network. |
| Linkage | The native build and the web build. They must link with no missing or duplicate symbols. |
| Each UGen of the package | `test/web/battery.spec.mjs` makes one SynthDef for each class file, with its default inputs. In SAB and postMessage mode, each must load and play with no `/fail` and no NaN, and stay in the CPU budget. A new UGen is in the battery with no change to the test. |
| The UGen's own sound | `test/web/plaits.spec.mjs`: each of the 24 Plaits engines in SAB and postMessage mode must make sound, with no NaN and no `/fail`. Write a spec of this kind for a new UGen. |
| Flux SynthDefs | Flux's `engine-synthdefs.integration.svelte.spec.ts` (in `pnpm test:container` and Flux CI) loads and plays each compiled Flux SynthDef in the engine package. It fails when a SynthDef uses a UGen that the engine does not have. |

## Checklist for the next third-party UGen

1. Read the UGen selection rule (project wiki): one UGen at a time, for what Flux needs.
2. Add its repository as a pinned submodule, if it is not in one already.
3. Add a `[[sources]]` entry to `ugens.toml`.
4. If the constructor uses the heap, write an `RTAlloc` patch. If the code keeps `inTable` in `ft`, write a plural-guest patch. Name the patches in the entry.
5. Run the tests of `prepare.py`, then `scripts/build-native.sh`, then the web build and the web tests.
6. Write a web spec that checks the UGen's sound, as `plaits.spec.mjs` does.
7. Increase the version in `engine-version.env` and open a pull request. After the merge, release (see the README).
8. In Flux, bump the engine and add a SynthDef that uses the UGen.

## isospin UGens

A new or changed isospin UGen needs no change to the manifest, the hook or the build scripts:

1. Release isospin with the UGen.
2. The daily `track.yml` workflow (or `scripts/track.py isospin --body <file>`) changes the version and SHA-256 of the `[isospin]` entry in `ugens.toml` and opens a pull request. A new SuperSonic release on the same day goes into the same pull request.
3. Merge it and release the engine. The battery tests the new UGen with no change.

To work on an isospin UGen before a release, set `ISOSPIN_DIR` to an isospin working copy (see "Change a UGen locally" in the README).
