// The load functions of the UGens that flux-engine adds to SuperSonic's
// engine. SC_Lib_Cintf.cpp includes this file and calls SC_ExtraPlugins_Load()
// after the built-in plugins.
#pragma once

// The static UGens of isospin (build/isospin, see extra-plugins.cmake).
#include "isospin_sc_static.h"

static inline void SC_ExtraPlugins_Load(InterfaceTable* table) {
    Isospin_Load(table);
}
