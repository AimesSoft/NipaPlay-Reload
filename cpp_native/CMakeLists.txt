cmake_minimum_required(VERSION 3.16)
project(nipaplay_native LANGUAGES CXX)

# 方便 clangd 调试
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

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

# ──── MSVC CRT 链接：必须使用动态 CRT (/MD) 以匹配 Flutter 宿主 ────
# Flutter Windows 使用 /MD（动态链接 vcruntime），如果 cpp_native 使用 /MT（静态），
# 会导致跨 FFI 边界的 CRT 不匹配：两套独立的堆、FILE*、errno 等，
# 释放对方分配的内存会造成堆损坏崩溃。CMake 默认 /MD，此处使用
# target 级属性确保仅影响 nipaplay_native，不污染父项目的其他目标。
if(MSVC)
    set_property(TARGET nipaplay_native PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    )
endif()

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
    # /arch:AVX2 ≈ -march=x86-64-v3：启用 AVX2 + FMA + BMI/BMI2 + POPCNT
    # 仅对 x86_64 目标生效；/arch:AVX2 是 x86 专用标志，ARM64 MSVC 不识别
    # Rust 侧 fdsm/nalgebra/image 已使用 x86-64-v3，此处必须对齐
    # Haswell(2013)+ / Zen(2017)+，覆盖所有能流畅运行 wgpu 渲染的 CPU
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
        target_compile_options(nipaplay_native PRIVATE
            $<$<CONFIG:Release>:/arch:AVX2>
        )
    endif()
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

# ──── 架构优化选项（Release only）────
#
# x86-64-v3 = AVX2 + BMI + BMI2 + FMA + LZCNT + MOVBE + POPCNT ≈ Haswell(2013)+
#   Rust 侧的 fdsm (MSDF 生成)、nalgebra (线性代数)、image (像素处理)
#   均为 SIMD 密集型负载，可从 AVX2 256-bit 向量与 FMA 获得显著收益。
#   cpp_native 侧的布局引擎虽为分支密集型，auto-vectorizer 收益有限，
#   但由于 Rust 侧已设定 target-cpu=x86-64-v3，应用整体 ISA 门槛
#   由 Rust 决定，此处必须对齐以避免混合 ISA 导致的潜在问题。
#   -mtune=generic 确保 Intel/AMD 调度策略一视同仁。
#
#   兼容性：Sandy Bridge/Ivy Bridge/Bulldozer 不支持 AVX2，
#   但这些 2010-2013 年的 CPU 无法流畅驱动 wgpu (DX12/Vulkan/Metal)，
#   实际使用 NipaPlay 的用户 CPU 均为 Haswell+ / Zen+。
#
# ARM64 Linux：armv8.2-a (+LSE 原子指令 / +FP16 半精度)
#   覆盖 Cortex-A76/A77/A78/X1/X2/X3/X4、Neoverse N1/N2、Apple M1+。
#   Raspberry Pi 4 (Cortex-A72, armv8.0-a) 不支持，但 wgpu 渲染
#   对 GPU 的要求已排除此类设备。
#   Android / iOS / macOS 不在此处设置：
#   Android NDK → abiFilters 已控制，且生态碎片化需保守；
#   Apple Clang → -arch arm64 隐含 armv8.5-a (M1+)，无需覆盖；
#   iOS         → CMAKE_OSX_ARCHITECTURES 已控制。
#
# ⚠️  macOS universal binary (arm64+x86_64) 不能在 CMakeLists 中
#   添加 -march 标志，因为同一编译选项会同时应用于两个架构切片，
#   而 -march=x86-64-v3 对 arm64 无效。build_macos.sh 已改为
#   分别编译两个架构再 lipo 合并，每个架构独立设置优化标志。

if(NOT MSVC AND NOT ANDROID)
    # ──── x86_64 目标检测 ────
    # 注意：macOS 交叉编译时 CMAKE_SYSTEM_PROCESSOR 反映宿主架构而非目标架构，
    # 例如 Apple Silicon Mac 上用 -DCMAKE_OSX_ARCHITECTURES="x86_64" 交叉编译时，
    # CMAKE_SYSTEM_PROCESSOR 仍为 arm64。因此必须同时检查 CMAKE_OSX_ARCHITECTURES。
    set(_NP_TARGET_X86_64 FALSE)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
        set(_NP_TARGET_X86_64 TRUE)
    endif()
    # macOS: CMAKE_OSX_ARCHITECTURES 指定实际编译目标
    if(APPLE AND DEFINED CMAKE_OSX_ARCHITECTURES)
        if("${CMAKE_OSX_ARCHITECTURES}" STREQUAL "x86_64")
            set(_NP_TARGET_X86_64 TRUE)
        elseif("${CMAKE_OSX_ARCHITECTURES}" MATCHES "arm64|aarch64")
            set(_NP_TARGET_X86_64 FALSE)
        endif()
    endif()

    set(_NP_CPP_ISA_INFO "default (no -march override)")
    if(_NP_TARGET_X86_64)
        target_compile_options(nipaplay_native PRIVATE
            $<$<CONFIG:Release>:-march=x86-64-v3>
            $<$<CONFIG:Release>:-mtune=generic>
        )
        set(_NP_CPP_ISA_INFO "x86-64-v3 (AVX2+FMA+BMI2+POPCNT)")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
        # Linux aarch64 (Docker arm64 构建、Asahi Linux 等)
        if(NOT APPLE AND NOT ANDROID)
            target_compile_options(nipaplay_native PRIVATE
                $<$<CONFIG:Release>:-march=armv8.2-a>
            )
            set(_NP_CPP_ISA_INFO "armv8.2-a (+LSE+FP16)")
        endif()
    endif()

    # ──── 编译诊断输出（需 flutter build -v 才可见）────
    # Flutter 默认日志级别会过滤 CMake configure 阶段的 message(STATUS) 输出，
    # 加 -v (verbose) 参数才能看到 ISA 优化信息。
    message(STATUS "")
    message(STATUS "── NipaPlay Native ISA Optimization ──")
    message(STATUS "  C++ (cpp_native): ${_NP_CPP_ISA_INFO}")
    # Rust 侧的 target-cpu 由 .cargo/config.toml 控制，此处显示期望值
    if(_NP_TARGET_X86_64)
        message(STATUS "  Rust (cargo):    x86-64-v3 (via .cargo/config.toml)")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64" AND NOT APPLE AND NOT ANDROID)
        message(STATUS "  Rust (cargo):    neoverse-n1 (via .cargo/config.toml)")
    elseif(APPLE)
        message(STATUS "  Rust (cargo):    Apple default (-arch arm64 / x86-64-v3 for Intel)")
    else()
        message(STATUS "  Rust (cargo):    default (no target-cpu override)")
    endif()
    message(STATUS "  Compiler:        ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
    message(STATUS "  Processor:       ${CMAKE_SYSTEM_PROCESSOR}")
    message(STATUS "")

    unset(_NP_TARGET_X86_64)
    unset(_NP_CPP_ISA_INFO)
endif()

# ──── MSVC 诊断输出（需 flutter build windows -v 才可见）────
# Flutter 默认日志级别会过滤 CMake configure 阶段的 message(STATUS) 输出，
# 加 -v (verbose) 参数才能看到 ISA 优化信息。
if(MSVC)
    message(STATUS "")
    message(STATUS "── NipaPlay Native ISA Optimization ──")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
        message(STATUS "  C++ (cpp_native): /arch:AVX2 (x86-64-v3 equivalent: AVX2+FMA+BMI2)")
        message(STATUS "  Rust (cargo):    x86-64-v3 (via .cargo/config.toml)")
    else()
        message(STATUS "  C++ (cpp_native): default (no /arch override)")
        message(STATUS "  Rust (cargo):    default (no target-cpu override)")
    endif()
    message(STATUS "  Compiler:        ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
    message(STATUS "  Processor:       ${CMAKE_SYSTEM_PROCESSOR}")
    message(STATUS "")
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
