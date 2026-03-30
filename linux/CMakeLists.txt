# Project-level configuration.
cmake_minimum_required(VERSION 3.10)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "NipaPlay")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.aimessoft.nipaplay")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# SteamOS environments can miss glibc headers under /usr/include, which breaks
# native plugin compilation (e.g. vendored libsmb2). Fall back to the Flatpak
# SDK headers when available.
if(CMAKE_SYSTEM_NAME MATCHES "Linux" AND NOT EXISTS "/usr/include/stdio.h")
  set(_np_flatpak_roots
    "/var/lib/flatpak/runtime/org.freedesktop.Sdk/x86_64/*/*/files"
    "/home/.steamos/offload/var/lib/flatpak/runtime/org.freedesktop.Sdk/x86_64/*/*/files"
  )
  file(GLOB _np_flatpak_candidates LIST_DIRECTORIES true ${_np_flatpak_roots})
  list(SORT _np_flatpak_candidates ORDER DESCENDING)

  set(_np_fallback_include "")
  set(_np_fallback_bits_include "")
  foreach(_np_sdk IN LISTS _np_flatpak_candidates)
    if(EXISTS "${_np_sdk}/include/stdio.h")
      set(_np_fallback_include "${_np_sdk}/include")
      if(EXISTS "${_np_sdk}/lib/x86_64-linux-gnu/include/bits/errno.h")
        set(_np_fallback_bits_include "${_np_sdk}/lib/x86_64-linux-gnu/include")
      endif()
      break()
    endif()
  endforeach()

  if(_np_fallback_include)
    set(NIPAPLAY_GLIBC_HEADERS_FALLBACK ON CACHE INTERNAL "Use Flatpak SDK headers for missing glibc headers" FORCE)
    # Use `-idirafter` (not `-isystem`) so C++ `#include_next` in libstdc++
    # can still resolve glibc headers (e.g. stdlib.h, math.h).
    add_compile_options("-idirafter${_np_fallback_include}")
    if(_np_fallback_bits_include)
      add_compile_options("-idirafter${_np_fallback_bits_include}")
    endif()
    # CMake feature checks (check_include_file, etc.) do not use
    # directory-level include_directories(). Feed fallback include paths to
    # those probes so generated config headers (e.g. libsmb2/config.h) are
    # correct.
    set(CMAKE_REQUIRED_INCLUDES "${_np_fallback_include}")
    if(_np_fallback_bits_include)
      list(APPEND CMAKE_REQUIRED_INCLUDES "${_np_fallback_bits_include}")
    endif()
    message(WARNING "glibc headers missing in /usr/include; using Flatpak SDK headers from ${_np_fallback_include}")
  else()
    message(FATAL_ERROR "glibc headers are missing in /usr/include and no Flatpak SDK fallback was found.")
  endif()
endif()

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
if(NOT GTK_INCLUDE_DIRS)
  # Some SteamOS setups have incomplete pkg-config metadata; recover common
  # GTK include paths explicitly.
  set(_np_gtk_fallback_dirs
    /usr/include/gtk-3.0
    /usr/include/atk-1.0
    /usr/include/at-spi-2.0
    /usr/include/at-spi2-atk/2.0
    /usr/include/pango-1.0
    /usr/include/harfbuzz
    /usr/include/glib-2.0
    /usr/lib/glib-2.0/include
    /usr/include/gdk-pixbuf-2.0
    /usr/include/cairo
    /usr/include/freetype2
    /usr/include/libpng16
    /usr/include/keybinder-3.0
    /usr/include/libayatana-appindicator3-0.1
    /usr/include/libayatana-indicator3-0.4
    /usr/include/libappindicator3-0.1
  )
  set(_np_gtk_include_dirs "")
  foreach(_np_dir IN LISTS _np_gtk_fallback_dirs)
    if(EXISTS "${_np_dir}")
      list(APPEND _np_gtk_include_dirs "${_np_dir}")
    endif()
  endforeach()
  if(_np_gtk_include_dirs)
    include_directories(SYSTEM ${_np_gtk_include_dirs})
    message(WARNING "GTK include paths from pkg-config are empty; using fallback include directories.")
  endif()
endif()

# Find libmpv for video playback support
pkg_check_modules(MPV QUIET IMPORTED_TARGET mpv)
if(MPV_FOUND)
  message(STATUS "Found libmpv: ${MPV_VERSION}")
else()
  message(WARNING "libmpv not found via pkg-config, will rely on runtime linking")
endif()

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Define the application target. To change its name, change BINARY_NAME above,
# not the value here, or `flutter run` will no longer work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Link libmpv if found
if(MPV_FOUND)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::MPV)
  message(STATUS "Linking with libmpv")
endif()

# Add mimalloc for better memory management (as recommended by player documentation)
find_package(PkgConfig REQUIRED)
# Ensure plugins (e.g. media_kit_libs_linux) do not force-build static
# mimalloc from source on systems missing full libc headers.
set(MIMALLOC_USE_STATIC_LIBS OFF CACHE BOOL "Prefer dynamic mimalloc where available" FORCE)
pkg_check_modules(MIMALLOC mimalloc QUIET)
if(MIMALLOC_FOUND)
  # use dynamically linked mimalloc
  target_link_libraries(${BINARY_NAME} PRIVATE ${MIMALLOC_LIBRARIES})
  target_include_directories(${BINARY_NAME} PRIVATE ${MIMALLOC_INCLUDE_DIRS})
  target_compile_options(${BINARY_NAME} PRIVATE ${MIMALLOC_CFLAGS_OTHER})
  message(STATUS "Using mimalloc for better memory management")
else()
  message(WARNING "mimalloc not found - using default allocator")
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
