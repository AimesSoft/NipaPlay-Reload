cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "fvp")
project(${PROJECT_NAME} LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "fvp_plugin")

add_library(${PLUGIN_NAME} SHARED
  "fvp_plugin.cc"
  ../lib/src/callbacks.cpp
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

target_link_libraries(${PLUGIN_NAME} PRIVATE EGL GLESv2)
#target_link_libraries(${PLUGIN_NAME} PRIVATE epoxy)
# flutter in snap: linker will try to resolve symbols and dependencies in libmdk.so.0, dependencies found in host OS but not snap are compatible with snap glibc
target_link_libraries(${PLUGIN_NAME} INTERFACE -Wl,--unresolved-symbols=ignore-in-shared-libs)
target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--enable-new-dtags -Wl,-z,origin)
# add runpath, shared libs of a release bundle is in lib dir, plugin must add $ORIGIN to runpath to find libmdk
set_target_properties(${PLUGIN_NAME} PROPERTIES
  BUILD_RPATH_USE_ORIGIN ON
  BUILD_RPATH "$ORIGIN"
  INSTALL_RPATH "$ORIGIN"
)
target_compile_options(${PLUGIN_NAME} PRIVATE -fno-rtti -fno-exceptions -ffunction-sections -fdata-sections)
target_compile_options(${PLUGIN_NAME} PRIVATE -Wno-unused-function) # https://github.com/wang-bin/fvp/issues/49
target_link_libraries(${PLUGIN_NAME} PRIVATE -Wl,--gc-sections)

include(../cmake/deps.cmake)
fvp_setup_deps()
target_link_libraries(${PLUGIN_NAME} PRIVATE mdk)
# List of absolute paths to libraries that should be bundled with the plugin
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
get_filename_component(MDK_LIB_DIR ${MDK_LIBRARY} DIRECTORY)
set(fvp_bundled_libraries
    ${MDK_RUNTIME}
    ${MDK_FFMPEG}
    ${MDK_LIB_DIR}/libc++.so.1
  PARENT_SCOPE
)
