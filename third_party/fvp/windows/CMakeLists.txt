# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "fvp")
project(${PROJECT_NAME} VERSION 0.33.1
    DESCRIPTION "Flutter video_player plugin via libmdk")
set(PROJECT_VERSION_TWEAK 0)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "fvp_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "fvp_plugin.cpp"
  "fvp_plugin.h"
)

string(TIMESTAMP COPYRIGHT_YEAR "%Y")
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/version.rc.in
  ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.rc
  @ONLY)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/fvp/fvp_plugin_c_api.h"
  "fvp_plugin_c_api.cpp"
  ../lib/src/callbacks.cpp
  "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.rc"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
#target_compile_definitions(${PLUGIN_NAME} PUBLIC DART_SHARED_LIB) # all platforms?

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:-D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR=1>")
target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<COMPILE_LANGUAGE:C,CXX>:-Os;-GR-;-EHs-c-a->")
target_link_options(${PLUGIN_NAME} PRIVATE -opt:ref,icf,lbr)

include(../cmake/deps.cmake)
fvp_setup_deps()
target_link_libraries(${PLUGIN_NAME} PRIVATE mdk)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
get_filename_component(MDK_LIB_DIR ${MDK_LIBRARY} DIRECTORY)
string(REPLACE "/lib/" "/bin/" MDK_BIN_DIR ${MDK_LIB_DIR})
set(fvp_bundled_libraries
    ${MDK_RUNTIME}
    ${MDK_FFMPEG}
    ${MDK_LIBASS}
  PARENT_SCOPE
)
