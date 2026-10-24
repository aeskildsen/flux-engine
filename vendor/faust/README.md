# Faust headers

The generated Faust UGens include these five headers. They are copied without change from Faust 2.85.9 (`faust --includedir`), so that the build does not need a Faust installation for them:

- `faust/dsp/dsp.h`
- `faust/export.h`
- `faust/gui/UI.h`
- `faust/gui/meta.h`
- `faust/misc.h`

License: LGPL-2.1-or-later with the Faust architecture exception (see the header of each file). The exception applies only while a file is not changed. Do not edit these files; copy them again from a new Faust version instead.

The `supercollider.cpp` architecture file is not here: `faust -a supercollider.cpp` takes it from the Faust installation. Its license is GPL-3.0-or-later with the same exception. `scripts/faust-static-ugen.py` changes its code, so the exception does not apply to the generated UGen sources: they are GPL-3.0-or-later, as the engine's scsynth sources are.
