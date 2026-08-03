cmake_minimum_required(VERSION 3.17)
project(nipaplay_ohos_native LANGUAGES CXX)

# Build the shared C++ core directly into the entry module so Hvigor packages
# libnipaplay_native.so under the arm64 native library directory in the HAP.
set(NP_LIB_TYPE SHARED CACHE STRING "NipaPlay native library type" FORCE)
add_subdirectory(
  "${CMAKE_CURRENT_LIST_DIR}/../../../../../cpp_native"
  "${CMAKE_CURRENT_BINARY_DIR}/nipaplay_native"
)

add_subdirectory(
  "${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/quickjs_c_bridge"
  "${CMAKE_CURRENT_BINARY_DIR}/quickjs_c_bridge"
)

# Cargokit currently has no HarmonyOS runner integration. Build the generated
# flutter_rust_bridge library with Rust's native OHOS target and copy it into
# Hvigor's native output directory so it is packaged alongside the C++ libs.
set(NP_RUST_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../../rust")
find_program(NP_CARGO_EXECUTABLE cargo REQUIRED)
get_filename_component(NP_OHOS_LLVM_BIN "${CMAKE_C_COMPILER}" DIRECTORY)
set(
  NP_OHOS_RUST_LINKER
  "${NP_OHOS_LLVM_BIN}/aarch64-unknown-linux-ohos-clang"
)
set(
  NP_OHOS_RUST_CXX
  "${NP_OHOS_LLVM_BIN}/aarch64-unknown-linux-ohos-clang++"
)

if(CMAKE_BUILD_TYPE MATCHES "^[Rr]elease$|^[Rr]elWithDebInfo$|^[Mm]inSizeRel$")
  set(NP_RUST_PROFILE "release")
  set(NP_RUST_PROFILE_ARGS "--release")
else()
  set(NP_RUST_PROFILE "debug")
  set(NP_RUST_PROFILE_ARGS)
endif()

set(
  NP_RUST_BUILT_LIBRARY
  "${NP_RUST_DIR}/target/aarch64-unknown-linux-ohos/${NP_RUST_PROFILE}/librust_lib_nipaplay.so"
)
set(
  NP_RUST_PACKAGED_LIBRARY
  "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/librust_lib_nipaplay.so"
)
file(GLOB_RECURSE NP_RUST_SOURCES CONFIGURE_DEPENDS "${NP_RUST_DIR}/src/*.rs")

add_custom_command(
  OUTPUT "${NP_RUST_PACKAGED_LIBRARY}"
  COMMAND
    "${CMAKE_COMMAND}" -E env
    "RUSTUP_TOOLCHAIN=1.93.0"
    "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=${NP_OHOS_RUST_LINKER}"
    "CC_aarch64_unknown_linux_ohos=${NP_OHOS_RUST_LINKER}"
    "CXX_aarch64_unknown_linux_ohos=${NP_OHOS_RUST_CXX}"
    "AR_aarch64_unknown_linux_ohos=${CMAKE_AR}"
    "${NP_CARGO_EXECUTABLE}" build
    --manifest-path "${NP_RUST_DIR}/Cargo.toml"
    --target aarch64-unknown-linux-ohos
    --features ohos
    --lib
    ${NP_RUST_PROFILE_ARGS}
  COMMAND
    "${CMAKE_COMMAND}" -E copy_if_different
    "${NP_RUST_BUILT_LIBRARY}"
    "${NP_RUST_PACKAGED_LIBRARY}"
  DEPENDS
    "${NP_RUST_DIR}/Cargo.toml"
    "${NP_RUST_DIR}/Cargo.lock"
    "${NP_RUST_DIR}/rust-toolchain.toml"
    ${NP_RUST_SOURCES}
  COMMENT "Building rust_lib_nipaplay for HarmonyOS arm64"
  USES_TERMINAL
  VERBATIM
)

add_custom_target(
  rust_lib_nipaplay ALL
  DEPENDS "${NP_RUST_PACKAGED_LIBRARY}"
)
