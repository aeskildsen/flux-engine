# The UGens that flux-engine adds to SuperSonic's engine. SuperSonic's
# dsp/scsynth/CMakeLists.txt includes this file when SCSYNTH_EXTRA_PLUGINS
# points to it (patches/supersonic-extra-plugins.patch adds that hook).

set(FLUX_ENGINE_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")

# The static UGens of isospin. scripts/prepare.sh puts them into
# build/isospin, from the isospin release or from a working copy. Their
# isospin.cmake sets the source list and the build settings of each source.
set(FLUX_ENGINE_ISOSPIN "${FLUX_ENGINE_ROOT}/build/isospin")
if(NOT EXISTS "${FLUX_ENGINE_ISOSPIN}/isospin.cmake")
    message(FATAL_ERROR "No ${FLUX_ENGINE_ISOSPIN}/isospin.cmake. Run scripts/prepare.sh first.")
endif()
include("${FLUX_ENGINE_ISOSPIN}/isospin.cmake")
list(APPEND SCSYNTH_PLUGIN_SOURCES ${ISOSPIN_SC_STATIC_SOURCES})

# extra-plugins.h includes isospin_sc_static.h.
set_property(SOURCE synth/server/SC_Lib_Cintf.cpp APPEND PROPERTY
    INCLUDE_DIRECTORIES "${ISOSPIN_SC_STATIC_DIR}")

set(SCSYNTH_EXTRA_PLUGINS_HEADER "${CMAKE_CURRENT_LIST_DIR}/extra-plugins.h")
