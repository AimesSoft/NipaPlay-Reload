cmake_minimum_required(VERSION 3.16)
project(nipaplay_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ──── 源文件列表 — 新增模块在此追加 ────
set(NATIVE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/nipaplay_native.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/string_utils.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/example_calculator.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/danmaku_layout.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/similarity_engine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/pinyin_dict.cpp
)

set(NATIVE_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/modules
)

# ──── 库类型 ────
# 由调用方（各平台 CMake）决定 SHARED / STATIC
# 默认 STATIC（iOS 必须静态链接）
if(NOT DEFINED NP_LIB_TYPE)
    set(NP_LIB_TYPE STATIC)
endif()

# ──── 跨平台属性（必须在 add_library 之前设置，作为目标属性初始值）────
# 位置无关代码：GCC/Clang → -fPIC，MSVC → 无需处理，CMake 自动适配
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# 符号可见性：GCC/Clang → -fvisibility=hidden，MSVC → 不自动导出
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
# 内联函数符号隐藏：GCC/Clang → -fvisibility-inlines-hidden，减小动态库体积
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

add_library(nipaplay_native ${NP_LIB_TYPE} ${NATIVE_SOURCES})
target_include_directories(nipaplay_native PUBLIC ${NATIVE_INCLUDES})

# ──── 公共编译宏（target 作用域）────
target_compile_definitions(nipaplay_native PRIVATE NIPAPLAY_NATIVE_BUILDING)

# ──── 平台特定编译选项（target 作用域）────
if(MSVC)
    target_compile_options(nipaplay_native PRIVATE
        /utf-8
        /EHsc
        /W4
        /Zc:__cplusplus
        /GR-
        $<$<CONFIG:Release>:/Ob3>
        $<$<CONFIG:Release>:/fp:fast>
    )
else()
    # Common flags for Apple & Linux
    target_compile_options(nipaplay_native PRIVATE
        -fno-rtti
        -fexceptions
        -Wall
        -Wextra
        -Wpedantic
        $<$<CONFIG:Debug>:-Og>
        $<$<CONFIG:Release>:-O3>
        $<$<CONFIG:Release>:-ffast-math>
    )
endif()

# ──── 安全启用 LTO/IPO ────
# CMake 自动匹配编译器 flag: MSVC → /GL+/LTCG, GCC/Clang → -flto
include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_supported OUTPUT ipo_error LANGUAGES CXX)
if(ipo_supported)
    set_target_properties(nipaplay_native PROPERTIES
        INTERPROCEDURAL_OPTIMIZATION_RELEASE ON
    )
else()
    message(WARNING "IPO/LTO not supported: ${ipo_error}")
endif()

# Android: 使用 c++_shared STL（与 Flutter 引擎一致）
if(ANDROID)
    find_library(CXX_SHARED c++_shared)
    if(CXX_SHARED)
        target_link_libraries(nipaplay_native PUBLIC ${CXX_SHARED})
    endif()
endif()
