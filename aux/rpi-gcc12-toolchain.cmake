# Cross toolchain for aarch64-linux-gnu using /opt/gcc-12-cross

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Toolchain sysroot
set(CMAKE_SYSROOT "/opt/gcc-12-cross/aarch64-linux-gnu-sysroot")

# Allow overriding from the command line/env, but default to qb_install_dir
if(NOT DEFINED QBT_STAGING_ROOT)
  set(QBT_STAGING_ROOT "/build-rpi/static/qbittorrent/build")
endif()

set(CMAKE_FIND_ROOT_PATH
    "${QBT_STAGING_ROOT}"
    "${CMAKE_SYSROOT}"
)

# Cross compilers
set(CMAKE_C_COMPILER   "/opt/gcc-12-cross/bin/aarch64-linux-gnu-gcc")
set(CMAKE_CXX_COMPILER "/opt/gcc-12-cross/bin/aarch64-linux-gnu-g++")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
