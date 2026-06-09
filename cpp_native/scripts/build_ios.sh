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

BUILD_DIR="${DERIVED_SOURCES_DIR:-${CPP_NATIVE_DIR}/build_ios}"

# 构建静态库（arm64 only for device, x86_64 for simulator）
ARCHS="${ARCHS_STANDARD:-arm64}"
for ARCH in ${ARCHS}; do
    cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}/${ARCH}" \
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
        -DNP_LIB_TYPE=STATIC \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"

    cmake --build "${BUILD_DIR}/${ARCH}" -j$(sysctl -n hw.ncpu)
done

# 如果多架构，用 lipo 合并；单架构则直接复制
if [ $(echo ${ARCHS} | wc -w) -gt 1 ]; then
    LIPO_ARGS=""
    for ARCH in ${ARCHS}; do
        LIPO_ARGS="${LIPO_ARGS} ${BUILD_DIR}/${ARCH}/libnipaplay_native.a"
    done
    lipo -create ${LIPO_ARGS} -output "${BUILD_DIR}/libnipaplay_native.a"
else
    # 单架构时 lipo 分支被跳过，需手动复制到统一路径
    SINGLE_ARCH=$(echo ${ARCHS} | awk '{print $1}')
    cp "${BUILD_DIR}/${SINGLE_ARCH}/libnipaplay_native.a" "${BUILD_DIR}/libnipaplay_native.a"
fi

# Copy to both BUILT_PRODUCTS_DIR and DERIVED_SOURCES_DIR (Xcode can find it)
SOURCE_LIB="${BUILD_DIR}/libnipaplay_native.a"
cp "${SOURCE_LIB}" "${BUILT_PRODUCTS_DIR}/"
mkdir -p "${DERIVED_SOURCES_DIR}"
DERIVED_LIB="${DERIVED_SOURCES_DIR}/libnipaplay_native.a"
if [ "${SOURCE_LIB}" != "${DERIVED_LIB}" ]; then
    cp "${SOURCE_LIB}" "${DERIVED_LIB}"
fi
