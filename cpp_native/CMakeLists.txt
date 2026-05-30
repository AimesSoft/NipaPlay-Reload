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
)

set(NATIVE_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/modules
)

# ──── 平台特定编译选项 ────
if(MSVC)
    add_compile_options(/utf-8 /EHsc /W4 /Zc:__cplusplus)
    add_definitions(-DNIPAPLAY_NATIVE_BUILDING)
    # Debug: /Od (default, no optimizations, best debugging experience)
    # Release: /O2 (default) + /fp:fast (aggressive FP optimizations)
    add_compile_options($<$<CONFIG:Release>:/fp:fast>)
else()
    # Common flags for Apple & Linux
    add_compile_options(-fno-rtti -fvisibility=hidden)
    add_definitions(-DNIPAPLAY_NATIVE_BUILDING)
    if(NOT APPLE)
        add_compile_options(-fPIC)
    endif()

    # Debug: -Og (optimize for debugging experience, preserves stack frames)
    add_compile_options($<$<CONFIG:Debug>:-Og>)

    # Release: -O3 -ffast-math (equivalent to -Ofast)
    # np_isnan/np_isinf (IEEE 754 bit-level) bypass -ffinite-math-only safely.
    add_compile_options($<$<CONFIG:Release>:-O3>)
    add_compile_options($<$<CONFIG:Release>:-ffast-math>)
endif()

# ──── 库类型 ────
# 由调用方（各平台 CMake）决定 SHARED / STATIC
# 默认 STATIC（iOS 必须静态链接）
if(NOT DEFINED NP_LIB_TYPE)
    set(NP_LIB_TYPE STATIC)
endif()

add_library(nipaplay_native ${NP_LIB_TYPE} ${NATIVE_SOURCES})
target_include_directories(nipaplay_native PUBLIC ${NATIVE_INCLUDES})

# Android: 使用 c++_shared STL（与 Flutter 引擎一致）
if(ANDROID)
    find_library(CXX_SHARED c++_shared)
    if(CXX_SHARED)
        target_link_libraries(nipaplay_native PUBLIC ${CXX_SHARED})
    endif()
endif()
