# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(nipaplay_smb2_library VERSION 0.0.1 LANGUAGES C)

# Build libsmb2 as a static library and link it into the plugin shared library.
# Keep options minimal to avoid pulling extra dependencies (Kerberos/GSSAPI).
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libraries" FORCE)
set(ENABLE_EXAMPLES OFF CACHE BOOL "Build example programs" FORCE)
set(ENABLE_LIBKRB5 OFF CACHE BOOL "Enable libkrb5 support" FORCE)
set(ENABLE_GSSAPI OFF CACHE BOOL "Enable gssapi support" FORCE)

# We link libsmb2 (static) into the plugin shared library; ensure PIC on
# platforms that require it (e.g. Linux).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(WIN32)
  # libsmb2 headers use _WINDOWS to determine SOCKET types.
  # Avoid Windows SDK winsock.h/winsock2.h redefinition conflicts.
  add_definitions(-D_WINDOWS -D_WINSOCKAPI_ -DWIN32_LEAN_AND_MEAN -DNOMINMAX)
endif()

# libsmb2 is a vendored dependency; Flutter builds run an "install" step and
# libsmb2's upstream install() rules are not needed here and can fail on CI.
set(_np_saved_skip_install_rules "${CMAKE_SKIP_INSTALL_RULES}")
set(CMAKE_SKIP_INSTALL_RULES ON)
add_subdirectory(
  "${CMAKE_CURRENT_LIST_DIR}/../third_party/libsmb2"
  "${CMAKE_CURRENT_BINARY_DIR}/libsmb2"
)
set(CMAKE_SKIP_INSTALL_RULES "${_np_saved_skip_install_rules}")
unset(_np_saved_skip_install_rules)

# When install rules are skipped, CMake may not generate the per-directory
# install script, but the parent install script will still try to include it.
set(_np_libsmb2_install_script "${CMAKE_CURRENT_BINARY_DIR}/libsmb2/cmake_install.cmake")
if(NOT EXISTS "${_np_libsmb2_install_script}")
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/libsmb2")
  file(WRITE "${_np_libsmb2_install_script}" "# Stub install script for vendored libsmb2\n")
endif()
unset(_np_libsmb2_install_script)

if(TARGET smb2)
  set_target_properties(smb2 PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()

add_library(nipaplay_smb2 SHARED
  "nipaplay_smb2.c"
)

set_target_properties(nipaplay_smb2 PROPERTIES
  PUBLIC_HEADER nipaplay_smb2.h
  OUTPUT_NAME "nipaplay_smb2"
)

target_compile_definitions(nipaplay_smb2 PUBLIC DART_SHARED_LIB)

target_link_libraries(nipaplay_smb2 PRIVATE smb2)

if(WIN32)
  # Needed for libsmb2 internal compatibility header (poll/WSAPoll).
  target_include_directories(
    nipaplay_smb2
    PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../third_party/libsmb2/lib"
  )
endif()

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(nipaplay_smb2 PRIVATE "-Wl,-z,max-page-size=16384")
endif()
