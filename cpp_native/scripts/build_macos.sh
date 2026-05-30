#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${DERIVED_SOURCES_DIR:-${CPP_NATIVE_DIR}/build_macos}"

cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DNP_LIB_TYPE=SHARED \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"

cmake --build "${BUILD_DIR}" -j$(sysctl -n hw.ncpu)

# 复制 dylib 到 Frameworks
cp "${BUILD_DIR}/libnipaplay_native.dylib" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"
