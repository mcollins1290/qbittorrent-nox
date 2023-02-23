cmake_minimum_required(VERSION 3.16)
include_guard(GLOBAL)

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)

set(TARGET_SYSROOT /build-rpi/source/static/qbittorrent/build)
set(CMAKE_SYSROOT ${TARGET_SYSROOT})
set(LIB_DIR ${TARGET_SYSROOT}/lib)

set(CROSS_COMPILER /opt/cross-pi-gcc/bin/arm-linux-gnueabihf)
set(CMAKE_C_COMPILER ${CROSS_COMPILER}-gcc)
set(CMAKE_CXX_COMPILER ${CROSS_COMPILER}-g++)

set(QT_COMPILER_FLAGS "-w -std=c++17 -static -mfloat-abi=hard -march=armv8-a -mtune=cortex-a72 -mfpu=crypto-neon-fp-armv8")
set(QT_LINKER_FLAGS "--static -static -Wl,--no-as-needed -L${LIB_DIR} -lpthread -pthread")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
