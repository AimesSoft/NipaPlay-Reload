# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_nipaplay")
set(PLUGIN_NAME "rust_lib_nipaplay_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

include("../cargokit/cmake/cargokit.cmake")
set(_RUST_MANIFEST_REL "../../rust")
if (NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${_RUST_MANIFEST_REL}/Cargo.toml")
  message(FATAL_ERROR
    "Failed to locate rust/Cargo.toml at ${CMAKE_CURRENT_SOURCE_DIR}/${_RUST_MANIFEST_REL}")
endif()
apply_cargokit(${PROJECT_NAME} "${_RUST_MANIFEST_REL}" rust_lib_nipaplay "")

add_library(
  ${PLUGIN_NAME} SHARED
  "rust_lib_nipaplay_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE "${${PROJECT_NAME}_cargokit_lib}")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_nipaplay_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  $<TARGET_FILE:${PLUGIN_NAME}>
  PARENT_SCOPE
)
