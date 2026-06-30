#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"
HOST_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Xcode Run Script 阶段的 PATH 不会继承 shell 配置，显式补上 Homebrew 路径
# 让 Apple Silicon (/opt/homebrew) 和 Intel (/usr/local) 都能找到 cmake 等工具
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

# Map Xcode configuration to CMake build type
if [ "${CONFIGURATION}" = "Debug" ]; then
    CMAKE_BUILD_TYPE="Debug"
else
    CMAKE_BUILD_TYPE="Release"
fi

BUILD_DIR="${DERIVED_SOURCES_DIR:-${CPP_NATIVE_DIR}/build_macos}"

# ──── 构建策略：分别编译 arm64 和 x86_64，再 lipo 合并 ────
# 不能使用 CMAKE_OSX_ARCHITECTURES="arm64;x86_64" 统一编译，
# 因为 -march=x86-64-v3 对 arm64 切片无效，
# 而 -march=armv8.2-a 对 x86_64 切片无效。
# 分别编译可确保每个架构切片获得独立的优化标志。

# 1) arm64 切片（Apple M1+，工具链默认 armv8.5-a 级别）
cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}/arm64" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DNP_LIB_TYPE=SHARED \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

cmake --build "${BUILD_DIR}/arm64" -j"${HOST_JOBS}"

# 2) x86_64 切片（Intel Mac，启用 x86-64-v3 = AVX2 + FMA + BMI2）
# CMakeLists.txt 通过 CMAKE_OSX_ARCHITECTURES="x86_64" 检测目标架构
# （Apple Silicon 交叉编译时 CMAKE_SYSTEM_PROCESSOR 仍为 arm64，不可靠）
cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}/x86_64" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DNP_LIB_TYPE=SHARED \
    -DCMAKE_OSX_ARCHITECTURES="x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

cmake --build "${BUILD_DIR}/x86_64" -j"${HOST_JOBS}"

# 3) lipo 合并为 universal dylib。Erika C ABI 由 erika_flutter 的
# CocoaPods script phase 负责下载/构建并复制到 app Frameworks 目录。
mkdir -p "${BUILD_DIR}"
lipo -create \
    "${BUILD_DIR}/arm64/libnipaplay_native.dylib" \
    "${BUILD_DIR}/x86_64/libnipaplay_native.dylib" \
    -output "${BUILD_DIR}/libnipaplay_native.dylib"

# 复制 dylib 到 Frameworks
mkdir -p "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
cp "${BUILD_DIR}/libnipaplay_native.dylib" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"

# Code sign the dylib (required for macOS app notarization)
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libnipaplay_native.dylib"
