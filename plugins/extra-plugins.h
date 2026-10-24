// The load functions of the UGens that flux-engine adds to SuperSonic's
// engine. SC_Lib_Cintf.cpp includes this file and calls SC_ExtraPlugins_Load()
// after the built-in plugins. Each UGen needs an entry here and a source in
// extra-plugins.cmake.
#pragma once

struct InterfaceTable;

// Faust UGens. The Faust supercollider.cpp architecture declares its load
// function with C linkage, and scripts/faust-static-ugen.py keeps it.
extern "C" {
void Woodbar_Load(InterfaceTable* table);
}

static inline void SC_ExtraPlugins_Load(InterfaceTable* table) {
    Woodbar_Load(table);
}
