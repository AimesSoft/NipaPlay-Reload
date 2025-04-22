# - Try to find MDK SDK and Abi
#
# MDK_FOUND - system has MDK
# MDK_INCLUDE_DIRS - the MDK include directory
# MDK_LIBRARIES - The MDK libraries
# MDK_VERSION_STRING -the version of MDK SDK found
# MDK_RUNTIME, MDK_RUNTIMES, MDK_FFMPEG, MDK_LIBASS, MDK_RUNTIME_DIR, MDK_PLUGINS
#
# target_link_libraries(tgt PRIVATE mdk) will add all flags

if(POLICY CMP0063) # visibility. since 3.3
  cmake_policy(SET CMP0063 NEW)
  set(CMAKE_POLICY_DEFAULT_CMP0063 NEW)
endif()

list(APPEND CMAKE_PREFIX_PATH ${CMAKE_CURRENT_LIST_DIR}/../..) # for find_library(), find_file() etc.

set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

if(APPLE)
  set(CMAKE_SHARED_MODULE_SUFFIX ".dylib") # default is so
endif()


function(setup_mdk_plugin tgt)
  set(STATIC_PLUGIN 0)
  list(LENGTH ARGN NB_ARGN)
  if(${NB_ARGN} GREATER 0)
    list(GET ARGN 0 ARGN_0)
    if(${ARGN_0} STREQUAL STATIC)
      set(STATIC_PLUGIN 1)
    endif()
  else()
    if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL Darwin AND CMAKE_PROJECT_NAME STREQUAL mdk) # MUST build plugin in source tree
      set(STATIC_PLUGIN 1)
    endif()
  endif()
  if(STATIC_PLUGIN)
    add_library(${tgt} STATIC)
    target_link_libraries(mdk PRIVATE ${tgt})
    target_include_directories(${tgt} PRIVATE ${MDK_ABI_INCLUDE_DIRS} ${MDK_SOURCE_DIR}/external/include)
    if(CMAKE_PROJECT_NAME STREQUAL mdk)
      target_include_directories(${tgt} PRIVATE ${MDK_SOURCE_DIR})
    endif()
    string(REPLACE "mdk-" "" PLUGIN_NAME ${tgt})
    set_property(TARGET mdk APPEND PROPERTY STATIC_PLUGINS ${PLUGIN_NAME})
  else()
    add_library(${tgt} MODULE)
    target_link_libraries(${tgt} PRIVATE mdk::abi)
  endif()
  target_compile_definitions(${tgt} PRIVATE $<IF:${STATIC_PLUGIN},BUILD_MDK_STATIC,BUILD_MDK_LIB>)
  if(STATIC_PLUGIN)
    return()
  endif()
  # TODO: mkdsym, exclude_libs_all
  if(CMAKE_PROJECT_NAME STREQUAL mdk)
# TODO: why RUNTIME_OUTPUT_DIRECTORY property does not work?
      # copy ${tgt} plugin to main dso dir, and modify the copy. original output is untouched for test
      add_custom_command(TARGET ${tgt} POST_BUILD
      # ${tgt} plugin is areadly in versioned dir, so TARGET_LINKER_FILE_NAME is enough, while TARGET_SONAME_FILE_NAME is for regular dso runtime instead of plugin
          COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${tgt}> $<TARGET_FILE_DIR:${CMAKE_PROJECT_NAME}>/$<TARGET_LINKER_FILE_NAME:${tgt}>
      )
  endif()
  if(APPLE)
    set_target_properties(${tgt} PROPERTIES
        MACOSX_RPATH ON
        FRAMEWORK OFF # only static plugins for ios, tvos, xros?
      )
    # https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html
    list(APPEND RPATH_DIRS @loader_path/.. @loader_path/../.. @loader_path/../../.. @loader_path/../../../..) # plugin is in Plugins, Plugins/foo, mdk.framework/Version/A, mdk.framework/Version/A/Libraries
    # -install_name @rpath/... is set by cmake
    if(CMAKE_PROJECT_NAME STREQUAL mdk)
      # copy ${tgt} plugin to main dso dir, and modify the copy. original output is untouched for test
      add_custom_command(TARGET ${tgt} POST_BUILD
      # change id from absolute path to relative one. a module has no id?
          COMMAND install_name_tool -id @rpath/$<TARGET_LINKER_FILE_NAME:${tgt}> $<TARGET_FILE_DIR:${CMAKE_PROJECT_NAME}>/$<TARGET_LINKER_FILE_NAME:${tgt}>
      # if plugin is in the same dir as mdk, change absolute path to @rpath/mdk is enough if loader_path is included in rpath and ${tgt} is located in the same dir of dependency
      # TODO: framework Libraries dir, Plugins dir, change to @rpath/mdk.framework/Versions/A/mdk
      COMMAND install_name_tool -change $<TARGET_FILE:${CMAKE_PROJECT_NAME}> @rpath/$<TARGET_SONAME_FILE_NAME:${CMAKE_PROJECT_NAME}>.framework/Versions/A/$<TARGET_SONAME_FILE_NAME:${CMAKE_PROJECT_NAME}> $<TARGET_FILE_DIR:${CMAKE_PROJECT_NAME}>/$<TARGET_LINKER_FILE_NAME:${tgt}>
      #COMMAND install_name_tool -change $<TARGET_FILE:${CMAKE_PROJECT_NAME}> @rpath/$<TARGET_SONAME_FILE_NAME:${CMAKE_PROJECT_NAME}> $<TARGET_FILE_DIR:${CMAKE_PROJECT_NAME}>/$<TARGET_LINKER_FILE_NAME:${tgt}>
      )
    endif()
  else()
    if(LINUX OR CMAKE_SYSTEM_NAME MATCHES "Linux")
      list(APPEND RPATH_DIRS "$ORIGIN" "$ORIGIN/lib" "$ORIGIN/../lib" "$ORIGIN/../../lib/${ARCH}")
    endif()
    install(TARGETS ${tgt}
      RUNTIME DESTINATION bin
      LIBRARY DESTINATION $<IF:$<BOOL:${WIN32}>,bin,lib>
      ARCHIVE DESTINATION lib
      FRAMEWORK DESTINATION lib
      )
    # TODO: linux, macos
    if(MSVC) # llvm-mingw can generate pdb too
      install(FILES $<TARGET_PDB_FILE:${tgt}> CONFIGURATIONS RelWithDebInfo Debug MinSizeRel DESTINATION bin OPTIONAL) #COMPILE_PDB_OUTPUT_DIRECTORY and COMPILE_PDB_NAME for static
    endif()
  endif()
  set_target_properties(${tgt} PROPERTIES
    BUILD_RPATH_USE_ORIGIN TRUE
    BUILD_RPATH "${RPATH_DIRS}"
    INSTALL_RPATH "${RPATH_DIRS}"
    )
endfunction(setup_mdk_plugin)

# Compute the installation prefix relative to this file.
get_filename_component(_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)
get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)
if(_IMPORT_PREFIX STREQUAL "/")
  set(_IMPORT_PREFIX "")
endif()

if(ANDROID_ABI)
  set(_IMPORT_ARCH ${ANDROID_ABI})
elseif(CMAKE_ANDROID_ARCH_ABI)
  set(_IMPORT_ARCH ${CMAKE_ANDROID_ARCH_ABI})
elseif(CMAKE_C_COMPILER_ARCHITECTURE_ID) # msvc
  set(_IMPORT_ARCH ${CMAKE_C_COMPILER_ARCHITECTURE_ID}) # ARMV7 ARM64 X86 x64
elseif(CMAKE_CXX_COMPILER_ARCHITECTURE_ID) # msvc. LANGUAGES has CXX but no C
  set(_IMPORT_ARCH ${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}) # ARMV7 ARM64 X86 x64
elseif(WIN32)
  set(_IMPORT_ARCH ${CMAKE_SYSTEM_PROCESSOR})
elseif(CMAKE_SYSTEM_NAME STREQUAL Linux)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "[aA].*[rR].*64")
    set(_IMPORT_ARCH arm64)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "[aA][rR][mM]")
    set(_IMPORT_ARCH armhf)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "64")
    set(_IMPORT_ARCH amd64)
  endif()
endif()
string(TOLOWER "${_IMPORT_ARCH}" _IMPORT_ARCH)
if(WIN32)
  if(_IMPORT_ARCH MATCHES armv7) #msvc
    set(_IMPORT_ARCH arm)
  elseif(_IMPORT_ARCH MATCHES amd64) #msvc
    set(_IMPORT_ARCH x64)
  endif()
endif()


if(CMAKE_PROJECT_NAME STREQUAL mdk)
  set(_IMPORT_PREFIX ${MDK_SOURCE_DIR}) #
endif()
#list(APPEND CMAKE_FIND_ROOT_PATH ${_IMPORT_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH) # for cross build, find paths out sysroot
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH) # for cross build, find paths out sysroot
if(CMAKE_PROJECT_NAME STREQUAL mdk)
  set(MDK_INCLUDE_DIR ${_IMPORT_PREFIX}/include)
  set(MDK_ABI_INCLUDE_DIR ${_IMPORT_PREFIX}/include)
else()
  find_path(MDK_INCLUDE_DIR mdk/global.h PATHS ${_IMPORT_PREFIX}/include)
  set(MDK_ABI_INCLUDE_DIR ${MDK_INCLUDE_DIR}/abi)
endif()

set(MDK_RUNTIME_DIR ${_IMPORT_PREFIX}/lib/${_IMPORT_ARCH})
if(WIN32)
  set(MDK_RUNTIME_DIR ${_IMPORT_PREFIX}/bin/${_IMPORT_ARCH})
endif()
find_library(MDK_LIBRARY NAMES mdk libmdk PATHS ${_IMPORT_PREFIX}/lib/${_IMPORT_ARCH}) # FIXME: may select host library
if(MDK_LIBRARY)
  if(APPLE)
    if(MDK_LIBRARY MATCHES "\.xcframework$")
# cmake 28
    else()
      set(MDK_FRAMEWORK ${MDK_LIBRARY})
      set(MDK_LIBRARY ${MDK_LIBRARY}/mdk) # was .framework, IMPORTED_LOCATION is file path
    endif()
  endif()
else()
  if(APPLE)
    set(MDK_XCFWK ${_IMPORT_PREFIX}/lib/mdk.xcframework)
    if(EXISTS ${MDK_XCFWK})
      if(CMAKE_SYSTEM_NAME STREQUAL iOS)
        if(${CMAKE_OSX_SYSROOT} MATCHES Simulator)
          file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/ios-*-simulator)
        else()
          file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/ios-arm64)
        endif()
      elseif(CMAKE_SYSTEM_NAME STREQUAL tvOS)
        if(${CMAKE_OSX_SYSROOT} MATCHES Simulator)
          file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/tvos-*-simulator)
        else()
          file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/tvos-arm64)
        endif()
      elseif(CMAKE_SYSTEM_NAME STREQUAL visionOS)
        if(${CMAKE_OSX_SYSROOT} MATCHES Simulator)
          file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/xros-*-simulator)
        else()
          file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/xros-arm64)
        endif()
      elseif(MACCATALYST) # MACCATALYST is not standard
        file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/ios-*-maccatalyst)
      else()
        file(GLOB MDK_FWK LIST_DIRECTORIES true ${MDK_XCFWK}/macos-*)
      endif()
      if(EXISTS ${MDK_FWK})
        set(MDK_FRAMEWORK ${MDK_FWK}/mdk.framework)
        set(MDK_LIBRARY ${MDK_FRAMEWORK}/mdk)
        set(MDK_RUNTIME_DIR ${MDK_FWK})
        list(APPEND CMAKE_PREFIX_PATH ${MDK_FWK}) # for find_library(), find_file() etc.
      endif()
    endif()
  endif()
endif()

file(GLOB _MDK_FFMPEG "${MDK_RUNTIME_DIR}/*ffmpeg*.*")
if(_MDK_FFMPEG)
  list(GET _MDK_FFMPEG 0 MDK_FFMPEG)
endif()
file(GLOB MDK_LIBASS "${MDK_RUNTIME_DIR}/libass*.*")
file(GLOB MDK_PLUGINS "${MDK_RUNTIME_DIR}/*mdk-*.[^p.]*[^m]") # exclude pdb, dsym

set(MDK_INCLUDE_DIRS ${MDK_INCLUDE_DIR})
set(MDK_ABI_INCLUDE_DIRS ${MDK_ABI_INCLUDE_DIR})
set(MDK_LIBRARIES ${MDK_LIBRARY})
mark_as_advanced(MDK_INCLUDE_DIRS MDK_ABI_INCLUDE_DIRS MDK_LIBRARIES MDK_FFMPEG MDK_LIBASS MDK_RUNTIME_DIR MDK_PLUGINS)

# TODO: show git version, read from module.h
if(MDK_INCLUDE_DIR AND EXISTS "${MDK_INCLUDE_DIR}/mdk/c/global.h")
  file(STRINGS "${MDK_INCLUDE_DIR}/mdk/c/global.h" mdk_version_str
       REGEX "^#[\t ]*define[\t ]+MDK_(MAJOR|MINOR|MICRO)[\t ]+[0-9]+$")

  unset(MDK_VERSION_STRING)
  foreach(VPART MAJOR MINOR MICRO)
    foreach(VLINE ${mdk_version_str})
      if(VLINE MATCHES "^#[\t ]*define[\t ]+MDK_${VPART}[\t ]+([0-9]+)$")
        set(MDK_VERSION_PART "${CMAKE_MATCH_1}")
        set(MDK_VERSION_${VPART} ${MDK_VERSION_PART})
        if(DEFINED MDK_VERSION_STRING)
          string(APPEND MDK_VERSION_STRING ".${MDK_VERSION_PART}")
        else()
          set(MDK_VERSION_STRING "${MDK_VERSION_PART}")
        endif()
        unset(MDK_VERSION_PART)
      endif()
    endforeach()
  endforeach()
endif()

include(FindPackageHandleStandardArgs)

if(CMAKE_PROJECT_NAME STREQUAL mdk)
  if(NOT TARGET mdk::abi)
    add_library(mdk::abi INTERFACE IMPORTED)
    #target_include_directories(mdk::abi INTERFACE ${MDK_ABI_INCLUDE_DIRS} ${MDK_SOURCE_DIR}/external/include)
    #target_link_libraries(mdk::abi INTERFACE mdk)
    #add_library(mdk::abi INTERFACE)
    set_target_properties(mdk::abi PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${MDK_ABI_INCLUDE_DIRS};${MDK_SOURCE_DIR}/external/include"
      INTERFACE_LINK_LIBRARIES "mdk"
    )
  endif()
  return()
endif()

if(WIN32)
  set(MDK_RUNTIME ${MDK_RUNTIME_DIR}/mdk.dll)
elseif(ANDROID)
  set(MDK_RUNTIME ${MDK_LIBRARY})
elseif(LINUX OR CMAKE_SYSTEM_NAME MATCHES "Linux")
  set(MDK_RUNTIME ${MDK_LIBRARY}.${MDK_VERSION_MAJOR})
endif()
if(MDK_RUNTIME)
  set(MDK_RUNTIMES ${MDK_RUNTIME} ${MDK_FFMPEG} ${MDK_LIBASS} ${MDK_PLUGINS})
  if(MDK_LIBASS)
    list(APPEND MDK_RUNTIMES ${MDK_LIBASS})
  endif()
  if(MDK_PLUGINS)
    list(APPEND MDK_RUNTIMES ${MDK_PLUGINS})
  endif()
endif()

if(MSVC)
  set(CXX_FLAG_NO_RTTI -GR-)
else()
  set(CXX_FLAG_NO_RTTI -fno-rtti)
endif()
add_library(mdk::abi SHARED IMPORTED)
set_target_properties(mdk::abi PROPERTIES
  IMPORTED_LOCATION "${MDK_LIBRARIES}"
  IMPORTED_IMPLIB "${MDK_LIBRARY}" # for win32, .lib import library
  INTERFACE_INCLUDE_DIRECTORIES "${MDK_ABI_INCLUDE_DIRS}"
  INTERFACE_COMPILE_OPTIONS "${CXX_FLAG_NO_RTTI}" #"$<IF:$<CXX_COMPILER_ID:MSVC>,-GR-,-fno-rtti>"
  INTERFACE_POSITION_INDEPENDENT_CODE ON
  #IMPORTED_SONAME "@rpath/mdk.framework/mdk"
  #IMPORTED_NO_SONAME 1 # -lmdk instead of full path
  )
if(APPLE)
  set_property(TARGET mdk::abi PROPERTY FRAMEWORK 0) # DO NOT search Headers in framework, search include/abi only
endif()

find_package_handle_standard_args(MDK
                                  REQUIRED_VARS MDK_LIBRARY MDK_INCLUDE_DIR
                                  VERSION_VAR MDK_VERSION_STRING)
add_library(mdk SHARED IMPORTED) # FIXME: ios needs CMAKE_SYSTEM_VERSION=9.0+(not DCMAKE_OSX_DEPLOYMENT_TARGET): Attempting to use @rpath without CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG being set.  This could be because you are using a Mac OS X version less than 10.5 or because CMake's platform configuration is corrupt
set_target_properties(mdk PROPERTIES
  IMPORTED_LOCATION "${MDK_LIBRARIES}"
  IMPORTED_IMPLIB "${MDK_LIBRARY}" # for win32, .lib import library
  INTERFACE_INCLUDE_DIRECTORIES "${MDK_INCLUDE_DIRS}"
  #IMPORTED_SONAME "@rpath/mdk.framework/mdk"
  #IMPORTED_NO_SONAME 1 # -lmdk instead of full path
  )
if(LINUX OR CMAKE_SYSTEM_NAME MATCHES "Linux")
  set_target_properties(mdk PROPERTIES
    INTERFACE_LINK_LIBRARIES "-Wl,-rpath-link,${MDK_RUNTIME_DIR}" # INTERFACE_LINK_OPTIONS for cmake3.16+. not required by mdk plugin because libc++-dev is always required
  )
endif()
if(APPLE)
  set_property(TARGET mdk PROPERTY FRAMEWORK 1)
else()
  if(ANDROID)
    add_library(mdk-ffmpeg SHARED IMPORTED)
    set_target_properties(mdk-ffmpeg PROPERTIES
            IMPORTED_LOCATION ${MDK_FFMPEG}
            )
    #add_dependencies(mdk mdk-ffmpeg)
    target_link_libraries(mdk INTERFACE mdk-ffmpeg) # ensure libffmpeg.so will be copied by gradle
    if(EXISTS "${MDK_LIBASS}")
      add_library(mdk-libass SHARED IMPORTED)
      set_target_properties(mdk-libass PROPERTIES
              IMPORTED_LOCATION "${MDK_LIBASS}")
      target_link_libraries(mdk INTERFACE mdk-libass)
    endif()
  endif()
endif()
