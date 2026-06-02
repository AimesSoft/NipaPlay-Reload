cmake_minimum_required(VERSION 3.10)
project(nipaplay_quickjs_c_bridge LANGUAGES CXX C)

set(QUICKJS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/quickjs")

add_library(nipaplay_quickjs_c_bridge SHARED
  "${QUICKJS_DIR}/cutils.c"
  "${QUICKJS_DIR}/libregexp.c"
  "${QUICKJS_DIR}/libunicode.c"
  "${QUICKJS_DIR}/quickjs.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/libfastdev_quickjs_runtime.cpp"
)

set_target_properties(nipaplay_quickjs_c_bridge PROPERTIES
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  OUTPUT_NAME quickjs_c_bridge_plugin
  POSITION_INDEPENDENT_CODE ON
  VISIBILITY_INLINES_HIDDEN YES
)
target_compile_features(nipaplay_quickjs_c_bridge PUBLIC cxx_std_17)
target_compile_definitions(nipaplay_quickjs_c_bridge PRIVATE
  CONFIG_VERSION="2021-03-27"
)
target_compile_options(nipaplay_quickjs_c_bridge PRIVATE
  $<$<COMPILE_LANGUAGE:C>:-Wno-implicit-const-int-float-conversion>
  $<$<COMPILE_LANGUAGE:C>:-Wno-int-conversion>
  $<$<COMPILE_LANGUAGE:C>:-Wno-unused-but-set-variable>
  $<$<COMPILE_LANGUAGE:C>:-Wno-unused-variable>
)
target_link_options(nipaplay_quickjs_c_bridge PRIVATE
  "-Wl,-Bsymbolic-functions"
)

# flutter_js ships an x64-only Linux bridge. Install the matching local build
# after plugin install scripts so Linux ARM64 gains JS support as well.
install(TARGETS nipaplay_quickjs_c_bridge
  LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}/lib"
  COMPONENT Runtime
)
