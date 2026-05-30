#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${DERIVED_SOURCES_DIR:-${CPP_NATIVE_DIR}/build_ios}"

# 构建静态库（arm64 only for device, x86_64 for simulator）
ARCHS="${ARCHS_STANDARD:-arm64}"
for ARCH in ${ARCHS}; do
    cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}/${ARCH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DNP_LIB_TYPE=STATIC \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-12.0}"

    cmake --build "${BUILD_DIR}/${ARCH}" -j$(sysctl -n hw.ncpu)
done

# 如果多架构，用 lipo 合并
if [ $(echo ${ARCHS} | wc -w) -gt 1 ]; then
    LIPO_ARGS=""
    for ARCH in ${ARCHS}; do
        LIPO_ARGS="${LIPO_ARGS} ${BUILD_DIR}/${ARCH}/libnipaplay_native.a"
    done
    lipo -create ${LIPO_ARGS} -output "${BUILD_DIR}/libnipaplay_native.a"
fi

cp "${BUILD_DIR}/libnipaplay_native.a" "${BUILT_PRODUCTS_DIR}/"
