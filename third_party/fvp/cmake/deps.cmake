macro(fvp_setup_deps)
  if(WIN32)
    set(MDK_SDK_PKG mdk-sdk-windows-desktop-vs2022.7z)
    if(CMAKE_CXX_COMPILER_ARCHITECTURE_ID MATCHES "[xX]64") # msvc
      set(MDK_SDK_PKG mdk-sdk-windows-desktop-vs2022-x64.7z)
    endif()
  elseif(ANDROID)
    set(MDK_SDK_PKG mdk-sdk-android.7z)
  elseif(LINUX OR CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(MDK_SDK_PKG mdk-sdk-linux.tar.xz)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "[xX].*64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "[aA][mM][dD]64")
      set(MDK_SDK_PKG mdk-sdk-linux-x64.tar.xz)
    endif()
  else()
  endif()
  if("$ENV{FVP_DEPS_URL}" MATCHES "^http") # github release: https://github.com/wang-bin/mdk-sdk/releases/latest/download
    set(FVP_DEPS_URL $ENV{FVP_DEPS_URL}) # TODO: md5
  else()
    set(FVP_DEPS_URL https://sourceforge.net/projects/mdk-sdk/files/nightly)
  endif()
  set(MDK_SDK_URL ${FVP_DEPS_URL}/${MDK_SDK_PKG})
  set(MDK_SDK_SAVE "${CMAKE_CURRENT_SOURCE_DIR}/${MDK_SDK_PKG}")

  set(DOWNLOAD_MDK_SDK OFF)
  message("FVP_DEPS_LATEST=$ENV{FVP_DEPS_LATEST}")
  # TODO: download from github option FVP_DEPS_LATEST_RELEASE=1
  if($ENV{FVP_DEPS_LATEST})
    if(EXISTS ${MDK_SDK_SAVE})
      message("Downloading latest md5")
      file(DOWNLOAD ${MDK_SDK_URL}.md5 ${MDK_SDK_SAVE}.md5 SHOW_PROGRESS)
      file(READ ${MDK_SDK_SAVE}.md5 MDK_SDK_MD5_LATEST)
      string(STRIP "${MDK_SDK_MD5_LATEST}" MDK_SDK_MD5_LATEST)
      file(MD5 ${MDK_SDK_SAVE} MDK_SDK_MD5_SAVE)
      message("md5 [${MDK_SDK_MD5_SAVE}] => [${MDK_SDK_MD5_LATEST}]")
      if(NOT MDK_SDK_MD5_LATEST STREQUAL MDK_SDK_MD5_SAVE)
        set(DOWNLOAD_MDK_SDK ON)
      endif()
    else()
      set(DOWNLOAD_MDK_SDK ON)
    endif()
  endif()

  if(DOWNLOAD_MDK_SDK OR NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/mdk-sdk/lib/cmake/FindMDK.cmake)
    if(DOWNLOAD_MDK_SDK OR NOT EXISTS ${MDK_SDK_SAVE})
      message("Downloading mdk-sdk from ${MDK_SDK_URL}")
      file(DOWNLOAD ${MDK_SDK_URL} ${MDK_SDK_SAVE} SHOW_PROGRESS)
      file(MD5 ${MDK_SDK_SAVE} MDK_SDK_MD5_SAVE)
      message("MDK_SDK_MD5_SAVE: ${MDK_SDK_MD5_SAVE}")
    endif()
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar "xvf" ${MDK_SDK_SAVE} # "--format=7zip"
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      OUTPUT_STRIP_TRAILING_WHITESPACE
      RESULT_VARIABLE EXTRACT_RET
    )
    # EXTRACT_RET is 0 even for empty files
    if(NOT EXTRACT_RET EQUAL 0 OR NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/mdk-sdk/lib/cmake/FindMDK.cmake)
      file(REMOVE ${MDK_SDK_SAVE})
      message(FATAL_ERROR "Failed to extract mdk-sdk. You can download manually from ${MDK_SDK_URL} and extract to ${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
  endif()
  include(${CMAKE_CURRENT_SOURCE_DIR}/mdk-sdk/lib/cmake/FindMDK.cmake)
endmacro()
