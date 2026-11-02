cmake_minimum_required(VERSION 3.17)
project(erika_flutter LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(PLUGIN_NAME erika_flutter_plugin)

get_filename_component(ERIKA_PACKAGE_ROOT
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." REALPATH)
# The published 0.3.3 runtime enables experimental NativeBuffer import.
# Mali drivers also crash compiling the ordinary Vulkan video shader. Build
# the same revision with GLES; hardware decoding remains enabled.
set(ERIKA_TARGET aarch64-unknown-linux-ohos)
set(ERIKA_USE_PREBUILT OFF)
set(ERIKA_COMPAT_REVISION 2bd4e02fe29807b23037e68f45c4eced159ac56b)
find_program(GIT_EXECUTABLE git REQUIRED)
if(NOT "$ENV{ERIKA_REPO_ROOT}" STREQUAL "")
  file(TO_CMAKE_PATH "$ENV{ERIKA_REPO_ROOT}" ERIKA_ROOT)
else()
  set(ERIKA_ROOT "${CMAKE_CURRENT_BINARY_DIR}/erika-source-v0.3.3")
  if(NOT EXISTS "${ERIKA_ROOT}/Cargo.toml")
    file(MAKE_DIRECTORY "${ERIKA_ROOT}")
    foreach(args IN ITEMS "init" "fetch;--depth=1;https://github.com/AimesSoft/liberika.git;${ERIKA_COMPAT_REVISION}" "checkout;--detach;FETCH_HEAD")
      execute_process(COMMAND "${GIT_EXECUTABLE}" ${args}
        WORKING_DIRECTORY "${ERIKA_ROOT}" RESULT_VARIABLE git_status)
      if(NOT git_status EQUAL 0)
        message(FATAL_ERROR "Could not prepare the pinned Erika compatibility source")
      endif()
    endforeach()
  endif()
endif()
execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse HEAD
  WORKING_DIRECTORY "${ERIKA_ROOT}" OUTPUT_VARIABLE erika_revision
  OUTPUT_STRIP_TRAILING_WHITESPACE RESULT_VARIABLE git_status)
if(NOT git_status EQUAL 0 OR NOT erika_revision STREQUAL ERIKA_COMPAT_REVISION)
  message(FATAL_ERROR "ERIKA_REPO_ROOT must be pinned to ${ERIKA_COMPAT_REVISION}")
endif()
set(ERIKA_COMPAT_PATCH "${ERIKA_PACKAGE_ROOT}/patches/ohos-gles-compat.patch")
execute_process(COMMAND "${GIT_EXECUTABLE}" apply --reverse --check "${ERIKA_COMPAT_PATCH}"
  WORKING_DIRECTORY "${ERIKA_ROOT}" RESULT_VARIABLE patch_applied
  OUTPUT_QUIET ERROR_QUIET)
if(NOT patch_applied EQUAL 0)
  execute_process(COMMAND "${GIT_EXECUTABLE}" apply "${ERIKA_COMPAT_PATCH}"
    WORKING_DIRECTORY "${ERIKA_ROOT}" RESULT_VARIABLE patch_status)
  if(NOT patch_status EQUAL 0)
    message(FATAL_ERROR "Could not apply the Erika OHOS renderer compatibility patch")
  endif()
endif()
set(ERIKA_RUNTIME
  "${ERIKA_ROOT}/target/${ERIKA_TARGET}/release/liberika_capi.so")

if(NOT DEFINED OHOS_SDK_NATIVE)
  message(FATAL_ERROR "OHOS_SDK_NATIVE is required to build Erika for OpenHarmony")
endif()

set(OHOS_LLVM_BIN "${OHOS_SDK_NATIVE}/llvm/bin")
set(OHOS_CXX_INCLUDE
  "${OHOS_SDK_NATIVE}/llvm/include/libcxx-ohos/include/c++/v1"
)
if(NOT EXISTS "${OHOS_CXX_INCLUDE}/vector")
  set(OHOS_CXX_INCLUDE "${OHOS_SDK_NATIVE}/llvm/include/c++/v1")
endif()
set(OHOS_BINDGEN_ARGS
  "--target=${ERIKA_TARGET} --sysroot=${OHOS_SDK_NATIVE}/sysroot -isystem ${OHOS_CXX_INCLUDE}"
)
if(NOT ERIKA_USE_PREBUILT)
  find_program(CARGO_EXECUTABLE cargo REQUIRED)
  file(GLOB_RECURSE ERIKA_RUST_SOURCES CONFIGURE_DEPENDS
    "${ERIKA_ROOT}/crates/*.rs"
    "${ERIKA_ROOT}/third_party/wgpu-hal/*.rs"
    "${ERIKA_ROOT}/xtask/*.rs"
  )
  list(APPEND ERIKA_RUST_SOURCES
    "${ERIKA_ROOT}/Cargo.toml"
    "${ERIKA_ROOT}/Cargo.lock"
    "${CMAKE_CURRENT_LIST_FILE}"
    "${ERIKA_COMPAT_PATCH}"
  )

  add_custom_command(
    OUTPUT "${ERIKA_RUNTIME}"
    COMMAND
      "${CMAKE_COMMAND}" -E env
        "OHOS_NDK_HOME=${OHOS_SDK_NATIVE}"
        "${CARGO_EXECUTABLE}" run --locked -q -p xtask --
        deps build --all --profile lgpl --target "${ERIKA_TARGET}"
    COMMAND
      "${CMAKE_COMMAND}" -E env
        "ERIKA_OHOS_VULKAN_VIDEO=0"
        "ERIKA_OHOS_GLES_ONLY=1"
        "ERIKA_NATIVE_PROFILE=lgpl"
        "ERIKA_NATIVE_TARGET=${ERIKA_TARGET}"
        "OHOS_NDK_HOME=${OHOS_SDK_NATIVE}"
        "LIBCLANG_PATH=${OHOS_SDK_NATIVE}/llvm/lib"
        "BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_ohos=${OHOS_BINDGEN_ARGS}"
        "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=${OHOS_LLVM_BIN}/aarch64-unknown-linux-ohos-clang"
        "CC_aarch64_unknown_linux_ohos=${OHOS_LLVM_BIN}/aarch64-unknown-linux-ohos-clang"
        "CXX_aarch64_unknown_linux_ohos=${OHOS_LLVM_BIN}/aarch64-unknown-linux-ohos-clang++"
        "AR_aarch64_unknown_linux_ohos=${OHOS_LLVM_BIN}/llvm-ar"
        "${CARGO_EXECUTABLE}" build --locked -p erika_capi
        --target "${ERIKA_TARGET}" --release
        --no-default-features --features libass,wgpu
    WORKING_DIRECTORY "${ERIKA_ROOT}"
    DEPENDS ${ERIKA_RUST_SOURCES}
    COMMENT "Building Erika OpenHarmony runtime"
    VERBATIM
  )
  add_custom_target(erika_ohos_runtime DEPENDS "${ERIKA_RUNTIME}")
endif()

add_library(erika_capi SHARED IMPORTED GLOBAL)
set_target_properties(erika_capi PROPERTIES IMPORTED_LOCATION "${ERIKA_RUNTIME}")
if(NOT ERIKA_USE_PREBUILT)
  add_dependencies(erika_capi erika_ohos_runtime)
endif()

add_library(${PLUGIN_NAME} SHARED erika_flutter_plugin.cpp)
if(NOT ERIKA_USE_PREBUILT)
  add_dependencies(${PLUGIN_NAME} erika_ohos_runtime)
endif()
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  OUTPUT_NAME "erika_flutter"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${ERIKA_PACKAGE_ROOT}/native/include"
)
target_compile_options(${PLUGIN_NAME} PRIVATE
  -fno-exceptions
  -ffunction-sections
  -fdata-sections
)
target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--gc-sections)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  erika_capi
  libace_napi.z.so
  libnative_window.so
  libhilog_ndk.z.so
)
add_custom_command(
  TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${ERIKA_RUNTIME}" "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/liberika_capi.so"
  COMMENT "Staging Erika OpenHarmony runtime beside the Flutter plugin"
  VERBATIM
)
