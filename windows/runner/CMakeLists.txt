cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "windows_native_video.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE
  "${CMAKE_BINARY_DIR}/libmpv/libmpv.dll.a"
  "opengl32.lib"
)
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_BINARY_DIR}/libmpv/include"
)

# ──── Release 编译优化：LTCG + 死代码消除 ────
# /O2：MSVC 速度优先整体优化（组合开关，已内含 /Oi 内建函数 / /Ob2 内联 / /Gy 函数级链接
#   /GF 字符串池化 / /Ot 速度优先，不重复列举这些子开关）
# /Gw：全局变量级链接（/O2 不含，每个全局变量独立 COMDAT 段）
# 链接器 /OPT:REF：消除未引用段（配合 /Gw 全局变量段 + /Gy 函数段，死代码消除减体积）
# 链接器 /OPT:ICF：COMDAT 折叠（消除重复函数/数据，配合 /Gy）
# INTERPROCEDURAL_OPTIMIZATION_RELEASE：MSVC → /GL + /LTCG（全程序优化，跨函数内联）
# 兼容性：与 cpp_native 的 INTERPROCEDURAL_OPTIMIZATION_RELEASE 对齐；
# /GL + /LTCG 与 Flutter 引擎 .lib 链接兼容（LTCG 仅作用于本 target 编译的 .o）；
# /OPT:REF /OPT:ICF 仅作用于本 target 链接，不影响 Flutter 引擎 .lib
set_target_properties(${BINARY_NAME} PROPERTIES
    INTERPROCEDURAL_OPTIMIZATION_RELEASE ON
)
target_compile_options(${BINARY_NAME} PRIVATE
    $<$<CONFIG:Release>:/O2>
    $<$<CONFIG:Release>:/Gw>
)
# 链接器死代码消除（Release only）：/Gw + /Gy 产生的独立段需链接器 /OPT:REF /OPT:ICF 才真正消除
# MSVC Release 链接器默认含 /OPT:REF /OPT:ICF，显式声明确保不被覆盖
target_link_options(${BINARY_NAME} PRIVATE
    $<$<CONFIG:Release>:/OPT:REF>
    $<$<CONFIG:Release>:/OPT:ICF>
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
