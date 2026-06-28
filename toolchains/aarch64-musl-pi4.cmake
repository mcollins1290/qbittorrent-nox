# toolchains/aarch64-musl-pi4.cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(TOOLCHAIN_ROOT "" CACHE PATH "Root of the musl cross toolchain")
set(TARGET_TRIPLE "aarch64-linux-musl" CACHE STRING "Cross compiler target triple")
set(SYSROOT "" CACHE PATH "Target sysroot")

list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
  TOOLCHAIN_ROOT
  TARGET_TRIPLE
  SYSROOT
  STAGING_PREFIX
)

if(NOT TOOLCHAIN_ROOT AND DEFINED ENV{TOOLCHAIN_ROOT})
  set(TOOLCHAIN_ROOT "$ENV{TOOLCHAIN_ROOT}" CACHE PATH "Root of the musl cross toolchain" FORCE)
endif()

if(NOT TOOLCHAIN_ROOT)
  message(FATAL_ERROR "TOOLCHAIN_ROOT is required. Pass -DTOOLCHAIN_ROOT=/path/to/musl-cross or set TOOLCHAIN_ROOT in the environment.")
endif()

if(NOT SYSROOT)
  set(SYSROOT "${TOOLCHAIN_ROOT}/${TARGET_TRIPLE}/sysroot" CACHE PATH "Target sysroot" FORCE)
endif()

set(CMAKE_SYSROOT "${SYSROOT}" CACHE PATH "Target sysroot" FORCE)

set(CMAKE_C_COMPILER   "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-gcc")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-g++")
set(CMAKE_AR           "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-ar")
set(CMAKE_RANLIB       "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-ranlib")
set(CMAKE_STRIP        "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-strip")

# Provided by the script at configure time; searched before sysroot.
set(STAGING_PREFIX "" CACHE PATH "Prefix where deps are staged (searched before sysroot)")

set(CMAKE_FIND_ROOT_PATH
  ${STAGING_PREFIX}
  ${CMAKE_SYSROOT}
)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER) # host tools are host tools
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Note: no tuning flags here; the build script owns CPU tuning/optimization.
