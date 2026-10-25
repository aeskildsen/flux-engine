// A loadable scsynth plugin with all static UGens of the isospin release
// (build/isospin), for the native reference render of the tests. The engine
// links the same sources statically; this file only adds the functions that
// scsynth looks for in a plugin file (api_version, server_type and load).
#include <SC_PlugIn.h>

#include "isospin_sc_static.h"

PluginLoad(Isospin) { Isospin_Load(inTable); }
