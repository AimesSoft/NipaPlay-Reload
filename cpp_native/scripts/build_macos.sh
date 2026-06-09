#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"
NIPAPLAY_ROOT="$(cd "${CPP_NATIVE_DIR}/.." && pwd)"
ERIKA_ROOT="${ERIKA_ROOT:-${NIPAPLAY_ROOT}/third_party/erika}"
ERIKA_NATIVE_PROFILE="${ERIKA_NATIVE_PROFILE:-lgpl}"
HOST_JOBS="$(sysctl -n hw.ncpu)"
ERIKA_RUST_TARGETS=("aarch64-apple-darwin" "x86_64-apple-darwin")

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

# 3) lipo 合并为 universal dylib
mkdir -p "${BUILD_DIR}"
lipo -create \
    "${BUILD_DIR}/arm64/libnipaplay_native.dylib" \
    "${BUILD_DIR}/x86_64/libnipaplay_native.dylib" \
    -output "${BUILD_DIR}/libnipaplay_native.dylib"

if [ ! -f "${ERIKA_ROOT}/Cargo.toml" ]; then
    echo "error: Erika source not found at ${ERIKA_ROOT}. Run git submodule update --init third_party/erika." >&2
    exit 1
fi

if [ "${CONFIGURATION}" = "Debug" ]; then
    ERIKA_CARGO_PROFILE="debug"
    ERIKA_CARGO_ARGS=()
else
    ERIKA_CARGO_PROFILE="release"
    ERIKA_CARGO_ARGS=(--release)
fi

echo "Building Erika C API from ${ERIKA_ROOT} (${ERIKA_CARGO_PROFILE})"
if command -v rustup >/dev/null 2>&1; then
    rustup target add "${ERIKA_RUST_TARGETS[@]}"
fi

ERIKA_DYLIB_INPUTS=()
for RUST_TARGET in "${ERIKA_RUST_TARGETS[@]}"; do
    ERIKA_TARGET_DIST="${ERIKA_ROOT}/third_party/dist/${RUST_TARGET}/${ERIKA_NATIVE_PROFILE}"
    ERIKA_FFMPEG_DIR="${ERIKA_ROOT}/third_party/dist/${RUST_TARGET}/${ERIKA_NATIVE_PROFILE}/ffmpeg"
    ERIKA_LIBASS_DIR="${ERIKA_TARGET_DIST}/libass"
    ERIKA_FREETYPE_DIR="${ERIKA_TARGET_DIST}/freetype"
    ERIKA_HARFBUZZ_DIR="${ERIKA_TARGET_DIST}/harfbuzz"
    ERIKA_FRIBIDI_DIR="${ERIKA_TARGET_DIST}/fribidi"
    ERIKA_FFMPEG_HEADERS="${ERIKA_FFMPEG_DIR}/include/libavformat/avformat.h"
    ERIKA_LIBASS_ARCHIVE="${ERIKA_LIBASS_DIR}/lib/libass.a"
    if [ ! -f "${ERIKA_FFMPEG_HEADERS}" ] || [ ! -f "${ERIKA_LIBASS_ARCHIVE}" ]; then
        echo "Erika native dependencies not found for ${RUST_TARGET}; building ${ERIKA_NATIVE_PROFILE} dependency profile with libass"
        (cd "${ERIKA_ROOT}" && cargo run -p xtask -- deps build --all --profile "${ERIKA_NATIVE_PROFILE}" --target "${RUST_TARGET}" --jobs "${HOST_JOBS}")
    fi

    echo "Building Erika C API for ${RUST_TARGET}"
    (cd "${ERIKA_ROOT}" && ERIKA_NATIVE_PROFILE="${ERIKA_NATIVE_PROFILE}" ERIKA_NATIVE_TARGET="${RUST_TARGET}" ERIKA_FFMPEG_DIR="${ERIKA_FFMPEG_DIR}" ERIKA_LIBASS_DIR="${ERIKA_LIBASS_DIR}" ERIKA_FREETYPE_DIR="${ERIKA_FREETYPE_DIR}" ERIKA_HARFBUZZ_DIR="${ERIKA_HARFBUZZ_DIR}" ERIKA_FRIBIDI_DIR="${ERIKA_FRIBIDI_DIR}" cargo build -p erika_capi --target "${RUST_TARGET}" --no-default-features --features libass "${ERIKA_CARGO_ARGS[@]}")

    ERIKA_DYLIB="${ERIKA_ROOT}/target/${RUST_TARGET}/${ERIKA_CARGO_PROFILE}/liberika_capi.dylib"
    if [ ! -f "${ERIKA_DYLIB}" ]; then
        echo "error: ${ERIKA_DYLIB} was not produced by Erika build." >&2
        exit 1
    fi
    ERIKA_DYLIB_INPUTS+=("${ERIKA_DYLIB}")
done

# 复制 dylib 到 Frameworks
cp "${BUILD_DIR}/libnipaplay_native.dylib" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"

ERIKA_BUNDLED_DYLIB="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/liberika_capi.dylib"
lipo -create "${ERIKA_DYLIB_INPUTS[@]}" -output "${ERIKA_BUNDLED_DYLIB}"
install_name_tool -id "@rpath/liberika_capi.dylib" "${ERIKA_BUNDLED_DYLIB}"

# Code sign the dylib (required for macOS app notarization)
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libnipaplay_native.dylib"

codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${ERIKA_BUNDLED_DYLIB}"
