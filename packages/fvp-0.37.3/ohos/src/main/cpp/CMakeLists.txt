cmake_minimum_required(VERSION 3.17)
set(PROJECT_NAME "fvp")
project(${PROJECT_NAME} LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "fvp_plugin")

add_library(${PLUGIN_NAME} SHARED
  "fvp_plugin.cpp"
  ../../../../lib/src/callbacks.cpp
)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  OUTPUT_NAME "fvp")
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_compile_options(${PLUGIN_NAME} PRIVATE -fno-rtti -fno-exceptions -ffunction-sections -fdata-sections)
target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--gc-sections)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  libace_napi.z.so
  libace_ndk.z.so
  libnative_window.so
  librawfile.z.so
)

include(../../../../cmake/deps.cmake)
fvp_setup_deps()
target_link_libraries(${PLUGIN_NAME} PRIVATE mdk)
