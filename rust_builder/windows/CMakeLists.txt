# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_nipaplay")
set(PLUGIN_NAME "rust_lib_nipaplay_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")

set(_RUST_MANIFEST_DIR "")
set(_RUST_MANIFEST_CANDIDATES
  "${CMAKE_CURRENT_SOURCE_DIR}/../../rust"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../rust"
)
foreach(_candidate IN LISTS _RUST_MANIFEST_CANDIDATES)
  if (EXISTS "${_candidate}/Cargo.toml")
    get_filename_component(_RUST_MANIFEST_DIR "${_candidate}" ABSOLUTE)
    break()
  endif()
endforeach()
if (NOT _RUST_MANIFEST_DIR)
  message(FATAL_ERROR "Failed to locate rust/Cargo.toml from ${CMAKE_CURRENT_SOURCE_DIR}")
endif()

apply_cargokit(${PROJECT_NAME} "${_RUST_MANIFEST_DIR}" rust_lib_nipaplay "")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/rust_lib_nipaplay/rust_lib_nipaplay_plugin_c_api.h"
  "rust_lib_nipaplay_plugin.cpp"
  "rust_lib_nipaplay_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(
  ${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

add_dependencies(${PLUGIN_NAME} "${PROJECT_NAME}_cargokit")

set(_RUST_CARGOKIT_IMPORT_LIB "${${PROJECT_NAME}_cargokit_lib}.lib")

target_link_libraries(
  ${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  dwmapi
  "${_RUST_CARGOKIT_IMPORT_LIB}"
)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_nipaplay_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  $<TARGET_FILE:${PLUGIN_NAME}>
  PARENT_SCOPE
)
