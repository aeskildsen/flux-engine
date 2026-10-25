# Builds Isospin.so: the static UGens of the isospin release (build/isospin,
# see scripts/prepare.py) as one plugin for native scsynth. The tests use it
# for the reference render. SC_INCLUDE_DIR is the include/SuperCollider folder
# of the scsynth that loads the plugin, so that the plugin API version agrees.
#
#   cmake -S test/native-plugin -B build/test/native-plugin -DSC_INCLUDE_DIR=...
cmake_minimum_required(VERSION 3.24)
project(isospin_native_plugin CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

if(NOT EXISTS "${SC_INCLUDE_DIR}/plugin_interface/SC_PlugIn.h")
    message(FATAL_ERROR "SC_INCLUDE_DIR (${SC_INCLUDE_DIR}) has no plugin_interface/SC_PlugIn.h")
endif()

set(ISOSPIN "${CMAKE_CURRENT_LIST_DIR}/../../build/isospin")
if(NOT EXISTS "${ISOSPIN}/isospin.cmake")
    message(FATAL_ERROR "No ${ISOSPIN}/isospin.cmake. Run scripts/prepare.py first.")
endif()
# Sets ISOSPIN_SC_STATIC_SOURCES and the build settings of each source.
include("${ISOSPIN}/isospin.cmake")

add_library(Isospin MODULE isospin_plugin.cpp ${ISOSPIN_SC_STATIC_SOURCES})
set_target_properties(Isospin PROPERTIES PREFIX "")
target_include_directories(Isospin PRIVATE
    "${SC_INCLUDE_DIR}/plugin_interface"
    "${SC_INCLUDE_DIR}/common"
    "${ISOSPIN_SC_STATIC_DIR}")
