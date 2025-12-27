# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(nipaplay_smb2_library VERSION 0.0.1 LANGUAGES C)

add_library(nipaplay_smb2 SHARED
  "nipaplay_smb2.c"
)

set_target_properties(nipaplay_smb2 PROPERTIES
  PUBLIC_HEADER nipaplay_smb2.h
  OUTPUT_NAME "nipaplay_smb2"
)

target_compile_definitions(nipaplay_smb2 PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(nipaplay_smb2 PRIVATE "-Wl,-z,max-page-size=16384")
endif()
