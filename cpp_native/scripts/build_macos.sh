#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"

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

cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DNP_LIB_TYPE=SHARED \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"

cmake --build "${BUILD_DIR}" -j$(sysctl -n hw.ncpu)

# 复制 dylib 到 Frameworks
cp "${BUILD_DIR}/libnipaplay_native.dylib" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"

# Code sign the dylib (required for macOS app notarization)
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libnipaplay_native.dylib"
