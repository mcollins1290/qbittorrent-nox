#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# build-qbittorrent-nox-static-aarch64-musl
# SCRIPT_VERSION: v0.0.39
#
# Fixes vs v0.0.38:
# - Make HTTPS tracker certificate verification work out-of-the-box on Debian/RPi OS
#   by configuring OpenSSL with system OPENSSLDIR:
#     --openssldir="/etc/ssl"
#
# Notes:
# - This does NOT change where OpenSSL installs libraries/headers (still --prefix="$PREFIX").
# - It only changes OpenSSL’s compiled-in default config/cert search base to match Debian.
###############################################################################

SCRIPT_NAME="build-qbittorrent-nox-static-aarch64-musl"
SCRIPT_VERSION="v0.0.39"

TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-/opt/gcc-14.2.0-musl-cross}"
TARGET_TRIPLE="${TARGET_TRIPLE:-aarch64-linux-musl}"
SYSROOT="${SYSROOT:-${TOOLCHAIN_ROOT}/${TARGET_TRIPLE}/sysroot}"
TOP="${TOP:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
TOOLCHAIN_FILE="${TOOLCHAIN_FILE:-$TOP/toolchains/aarch64-musl-gcc14-pi4.cmake}"

HOST_CC="${HOST_CC:-/usr/bin/gcc}"
HOST_CXX="${HOST_CXX:-/usr/bin/g++}"

QBT_VER="${QBT_VER:-5.1.4}"
LT_VER="${LT_VER:-2.0.11}"
OPENSSL_VER="${OPENSSL_VER:-3.5.5}"
ZLIB_VER="${ZLIB_VER:-1.3.2}"
BOOST_VER="${BOOST_VER:-1.90.0}"
QT_VER="${QT_VER:-6.10.2}"

DL="${DL:-$TOP/dl}"
SRC="${SRC:-$TOP/src}"
BUILD="${BUILD:-$TOP/build}"
OUT="${OUT:-$TOP/out}"
PREFIX="${PREFIX:-$OUT/${TARGET_TRIPLE}}"
HOST_QT_PREFIX="${HOST_QT_PREFIX:-$OUT/host-qt-${QT_VER}}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$TOP/artifacts}"

JOBS="${JOBS:-$(nproc)}"
STRIP_BIN="${STRIP_BIN:-1}"

QT_SHA256="${QT_SHA256:-}"
OPENSSL_SHA256="${OPENSSL_SHA256:-}"
ZLIB_SHA256="${ZLIB_SHA256:-}"
LT_SHA256="${LT_SHA256:-}"

QBT_SHA256_TGZ="${QBT_SHA256_TGZ:-24639f407b807ce94bbef1d07528215b6c4397866a3cb5a5a2278e277ca7652a}"
BOOST_SHA256_TGZ="${BOOST_SHA256_TGZ:-e848446c6fec62d8a96b44ed7352238b3de040b8b9facd4d6963b32f541e00f5}"

# System OpenSSL directory on Debian/RPi OS (config + CA store conventions)
OPENSSL_SYSTEM_DIR="${OPENSSL_SYSTEM_DIR:-/etc/ssl}"

msg() { printf "\n\033[1;36m==>\033[0m %s\n" "$*"; }
die() { printf "\n\033[1;31merror:\033[0m %s\n" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

usage() {
  cat <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION}

Usage:
  $0 [--clean] [--rebuild] [--distclean] [--no-strip] [--jobs N] [--help]
EOF
}

rm_rf_safe() {
  local p="$1"
  [[ -n "$p" ]] || die "rm_rf_safe: empty path"
  [[ "$p" != "/" ]] || die "rm_rf_safe: refusing to delete /"
  [[ "$p" != "." ]] || die "rm_rf_safe: refusing to delete ."
  rm -rf -- "$p"
}

clean() {
  msg "Cleaning build outputs (keeping downloads cache: $DL)"
  rm_rf_safe "$BUILD"
  rm_rf_safe "$SRC"
  rm_rf_safe "$OUT"
  rm_rf_safe "$ARTIFACTS_DIR"
}

distclean() {
  msg "Distclean (removing everything including downloads cache: $DL)"
  clean
  rm_rf_safe "$DL"
}

sha256_check() {
  local file="$1" expected="$2"
  [[ -z "$expected" ]] && return 0
  echo "${expected}  ${file}" | sha256sum -c -
}

fetch() {
  local url="$1" out="$2" sha="${3:-}"
  mkdir -p "$(dirname "$out")"
  if [[ ! -f "$out" ]]; then
    msg "Downloading: $url"
    curl -L --fail --retry 3 --retry-delay 2 -o "$out" "$url"
  else
    msg "Using cached: $out"
  fi
  if [[ -n "$sha" ]]; then
    msg "Verifying sha256: $(basename "$out")"
    sha256_check "$out" "$sha"
  else
    msg "No sha256 provided for $(basename "$out") (skipping verification)"
  fi
}

extract() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  msg "Extract: $(basename "$archive")"
  tar -xf "$archive" -C "$dest"
}

cmake_cfg() {
  local src_dir="$1" build_dir="$2"
  shift 2
  cmake -G Ninja -S "$src_dir" -B "$build_dir" "$@"
}

cmake_build_install() {
  local build_dir="$1"
  cmake --build "$build_dir" --parallel "$JOBS"
  cmake --install "$build_dir"
}

DO_CLEAN=0
DO_REBUILD=0
DO_DISTCLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) DO_CLEAN=1; shift ;;
    --rebuild) DO_REBUILD=1; shift ;;
    --distclean) DO_DISTCLEAN=1; shift ;;
    --no-strip) STRIP_BIN=0; shift ;;
    --jobs) shift; [[ $# -gt 0 ]] || die "--jobs requires a value"; JOBS="$1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ "$DO_REBUILD" == "1" ]]; then DO_CLEAN=1; fi

msg "${SCRIPT_NAME} ${SCRIPT_VERSION}"
msg "Host: $(uname -a)"
msg "Target: ${TARGET_TRIPLE}"
msg "Toolchain root: ${TOOLCHAIN_ROOT}"
msg "Sysroot: ${SYSROOT}"
msg "Toolchain file: ${TOOLCHAIN_FILE}"
msg "Jobs: ${JOBS}"
msg "Strip: ${STRIP_BIN}"
msg "OpenSSL OPENSSLDIR: ${OPENSSL_SYSTEM_DIR}"

if [[ "$DO_DISTCLEAN" == "1" ]]; then
  distclean
  if [[ "$DO_REBUILD" != "1" ]]; then
    msg "Distclean complete."
    exit 0
  fi
elif [[ "$DO_CLEAN" == "1" ]]; then
  clean
fi

need curl; need tar; need cmake; need ninja; need perl; need python3; need pkg-config; need make
need g++; need file; need readelf; need sha256sum

[[ -x "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-gcc" ]] || die "cross gcc not found"
[[ -d "$SYSROOT" ]] || die "SYSROOT not found: $SYSROOT"
[[ -f "$TOOLCHAIN_FILE" ]] || die "TOOLCHAIN_FILE not found: $TOOLCHAIN_FILE"
[[ -x "$HOST_CC" ]] || die "HOST_CC not executable: $HOST_CC"
[[ -x "$HOST_CXX" ]] || die "HOST_CXX not executable: $HOST_CXX"

mkdir -p "$DL" "$SRC" "$BUILD" "$OUT" "$PREFIX" "$ARTIFACTS_DIR" "$HOST_QT_PREFIX"

export PATH="${TOOLCHAIN_ROOT}/bin:${PATH}"
export CC="${TARGET_TRIPLE}-gcc"
export CXX="${TARGET_TRIPLE}-g++"
export AR="${TARGET_TRIPLE}-ar"
export RANLIB="${TARGET_TRIPLE}-ranlib"
export STRIP="${TARGET_TRIPLE}-strip"

export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
unset PKG_CONFIG_PATH || true

TUNE="-mcpu=cortex-a72 -mtune=cortex-a72"
export CFLAGS="${CFLAGS:- -O2 -pipe $TUNE }"
export CXXFLAGS="${CXXFLAGS:- -O2 -pipe $TUNE }"
export LDFLAGS="${LDFLAGS:- -static }"
export CMAKE_PREFIX_PATH="$PREFIX"

ZLIB_URL="https://zlib.net/zlib-${ZLIB_VER}.tar.xz"
OPENSSL_URL="https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz"
BOOST_URL="https://github.com/boostorg/boost/releases/download/boost-${BOOST_VER}/boost-${BOOST_VER}-b2-nodocs.tar.gz"
LT_URL="https://github.com/arvidn/libtorrent/releases/download/v${LT_VER}/libtorrent-rasterbar-${LT_VER}.tar.gz"
QBT_URL="https://downloads.sourceforge.net/project/qbittorrent/qbittorrent/qbittorrent-${QBT_VER}/qbittorrent-${QBT_VER}.tar.gz"

QTBASE_URL="https://download.qt.io/official_releases/qt/${QT_VER%.*}/${QT_VER}/submodules/qtbase-everywhere-src-${QT_VER}.tar.xz"
QTTOOLS_URL="https://download.qt.io/official_releases/qt/${QT_VER%.*}/${QT_VER}/submodules/qttools-everywhere-src-${QT_VER}.tar.xz"

build_zlib() {
  msg "=== zlib ${ZLIB_VER} (static, non-CMake) ==="
  local a="$DL/zlib-${ZLIB_VER}.tar.xz"
  fetch "$ZLIB_URL" "$a" "$ZLIB_SHA256"
  rm -rf "$SRC/zlib-${ZLIB_VER}"
  extract "$a" "$SRC"

  pushd "$SRC/zlib-${ZLIB_VER}" >/dev/null
  rm -f Makefile configure.log
  msg "Configure zlib (static)"
  CHOST="$TARGET_TRIPLE" CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS" \
    ./configure --static --prefix="$PREFIX"
  msg "Build zlib"; make -j"$JOBS"
  msg "Install zlib"; make install
  popd >/dev/null
}

build_openssl() {
  msg "=== OpenSSL ${OPENSSL_VER} ==="
  local a="$DL/openssl-${OPENSSL_VER}.tar.gz"
  fetch "$OPENSSL_URL" "$a" "$OPENSSL_SHA256"
  rm -rf "$SRC/openssl-${OPENSSL_VER}"
  extract "$a" "$SRC"

  pushd "$SRC/openssl-${OPENSSL_VER}" >/dev/null
  make clean >/dev/null 2>&1 || true

  msg "Configure OpenSSL (static, OPENSSLDIR=${OPENSSL_SYSTEM_DIR})"
  ./Configure linux-aarch64 no-shared no-tests no-legacy \
    --prefix="$PREFIX" --openssldir="${OPENSSL_SYSTEM_DIR}" -static \
    ${CFLAGS} ${LDFLAGS}

  msg "Build OpenSSL"; make -j"$JOBS"
  msg "Install OpenSSL"; make install_sw
  popd >/dev/null
}

build_boost() {
  msg "=== Boost ${BOOST_VER} ==="
  local a="$DL/boost-${BOOST_VER}.tar.gz"
  fetch "$BOOST_URL" "$a" "$BOOST_SHA256_TGZ"
  rm -rf "$SRC/boost-${BOOST_VER}"
  extract "$a" "$SRC"

  pushd "$SRC/boost-${BOOST_VER}" >/dev/null
  msg "Bootstrap b2"; ./bootstrap.sh
  local ucfg="$BUILD/boost-user-config.jam"
  mkdir -p "$BUILD"
  cat >"$ucfg" <<EOF
using gcc : musl : ${TARGET_TRIPLE}-g++ :
  <compileflags>"$CXXFLAGS"
  <linkflags>"$LDFLAGS"
  ;
EOF
  msg "Build Boost (static)"
  ./b2 -j"$JOBS" --user-config="$ucfg" toolset=gcc-musl target-os=linux \
    threading=multi variant=release link=static runtime-link=static \
    cxxflags="$CXXFLAGS" cflags="$CFLAGS" linkflags="$LDFLAGS" \
    --prefix="$PREFIX" \
    --with-system --with-chrono --with-date_time --with-random --with-atomic --with-thread \
    --with-regex --with-filesystem --with-program_options \
    install
  popd >/dev/null
}

build_libtorrent() {
  msg "=== libtorrent-rasterbar ${LT_VER} ==="
  local a="$DL/libtorrent-rasterbar-${LT_VER}.tar.gz"
  fetch "$LT_URL" "$a" "$LT_SHA256"
  rm -rf "$SRC/libtorrent-rasterbar-${LT_VER}"
  extract "$a" "$SRC"

  local b="$BUILD/libtorrent-${LT_VER}"
  rm -rf "$b"
  cmake_cfg "$SRC/libtorrent-rasterbar-${LT_VER}" "$b" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DSTAGING_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -Dstatic_runtime=ON \
    -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF -Dpython-bindings=OFF \
    -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DZLIB_ROOT="$PREFIX"
  cmake_build_install "$b"
}

fetch_qtbase() {
  msg "=== QtBase source ${QT_VER} ==="
  local a="$DL/qtbase-everywhere-src-${QT_VER}.tar.xz"
  fetch "$QTBASE_URL" "$a" "$QT_SHA256"
  rm -rf "$SRC/qtbase-everywhere-src-${QT_VER}"
  extract "$a" "$SRC"
}

fetch_qttools() {
  msg "=== QtTools source ${QT_VER} ==="
  local a="$DL/qttools-everywhere-src-${QT_VER}.tar.xz"
  fetch "$QTTOOLS_URL" "$a" "$QT_SHA256"
  rm -rf "$SRC/qttools-everywhere-src-${QT_VER}"
  extract "$a" "$SRC"
}

build_qtbase_host() {
  msg "=== QtBase (host) ${QT_VER} ==="
  local srcdir="$SRC/qtbase-everywhere-src-${QT_VER}"
  local b="$BUILD/qtbase-host-${QT_VER}"
  rm -rf "$b"

  env -u CC -u CXX -u AR -u RANLIB -u STRIP \
      -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH \
      -u CMAKE_PREFIX_PATH -u CMAKE_TOOLCHAIN_FILE -u SYSROOT -u TARGET_TRIPLE \
      CFLAGS="-O2 -pipe" CXXFLAGS="-O2 -pipe" LDFLAGS="" \
  cmake -G Ninja -S "$srcdir" -B "$b" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$HOST_QT_PREFIX" \
    -DCMAKE_C_COMPILER="$HOST_CC" \
    -DCMAKE_CXX_COMPILER="$HOST_CXX" \
    -DCMAKE_PREFIX_PATH="/usr;/usr/local" \
    -DZLIB_ROOT="/usr" \
    -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    -DQT_FEATURE_gui=OFF -DQT_FEATURE_widgets=OFF \
    -DQT_FEATURE_opengl=OFF -DQT_FEATURE_opengles2=OFF

  env -u CC -u CXX -u AR -u RANLIB -u STRIP \
      -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH \
      -u CMAKE_PREFIX_PATH -u CMAKE_TOOLCHAIN_FILE -u SYSROOT -u TARGET_TRIPLE \
  cmake --build "$b" --parallel "$JOBS"

  env -u CC -u CXX -u AR -u RANLIB -u STRIP \
      -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH \
      -u CMAKE_PREFIX_PATH -u CMAKE_TOOLCHAIN_FILE -u SYSROOT -u TARGET_TRIPLE \
  cmake --install "$b"
}

build_qtbase_target() {
  msg "=== QtBase (target static) ${QT_VER} ==="
  local srcdir="$SRC/qtbase-everywhere-src-${QT_VER}"
  local b="$BUILD/qtbase-target-${QT_VER}"
  rm -rf "$b"

  cmake_cfg "$srcdir" "$b" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DSTAGING_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_HOST_PATH="$HOST_QT_PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    -DQT_FEATURE_gui=OFF -DQT_FEATURE_widgets=OFF \
    -DQT_FEATURE_opengl=OFF -DQT_FEATURE_opengles2=OFF \
    -DQT_FEATURE_egl=OFF -DQT_FEATURE_dbus=OFF -DQT_FEATURE_printsupport=OFF \
    -DQT_FEATURE_sql=ON -DQT_FEATURE_sql_sqlite=ON \
    \
    -DQT_FEATURE_openssl=ON \
    -DQT_FEATURE_openssl_linked=ON \
    \
    -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DZLIB_ROOT="$PREFIX"
  cmake_build_install "$b"
}

build_qttools_host() {
  msg "=== QtTools (host, for Linguist tools) ${QT_VER} ==="
  local srcdir="$SRC/qttools-everywhere-src-${QT_VER}"
  local b="$BUILD/qttools-host-${QT_VER}"
  rm -rf "$b"

  env -u CC -u CXX -u AR -u RANLIB -u STRIP \
      -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH \
      -u CMAKE_TOOLCHAIN_FILE -u SYSROOT -u TARGET_TRIPLE \
      CFLAGS="-O2 -pipe" CXXFLAGS="-O2 -pipe" LDFLAGS="" \
  cmake -G Ninja -S "$srcdir" -B "$b" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$HOST_QT_PREFIX" \
    -DCMAKE_C_COMPILER="$HOST_CC" \
    -DCMAKE_CXX_COMPILER="$HOST_CXX" \
    -DCMAKE_PREFIX_PATH="$HOST_QT_PREFIX;/usr;/usr/local" \
    -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF

  env -u CC -u CXX -u AR -u RANLIB -u STRIP \
      -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH \
      -u CMAKE_TOOLCHAIN_FILE -u SYSROOT -u TARGET_TRIPLE \
  cmake --build "$b" --parallel "$JOBS"

  env -u CC -u CXX -u AR -u RANLIB -u STRIP \
      -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH \
      -u CMAKE_TOOLCHAIN_FILE -u SYSROOT -u TARGET_TRIPLE \
  cmake --install "$b"
}

build_qttools_target() {
  msg "=== QtTools (target) ${QT_VER} ==="
  local srcdir="$SRC/qttools-everywhere-src-${QT_VER}"
  local b="$BUILD/qttools-target-${QT_VER}"
  rm -rf "$b"

  cmake_cfg "$srcdir" "$b" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DSTAGING_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_HOST_PATH="$HOST_QT_PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF
  cmake_build_install "$b"
}

build_qbittorrent() {
  msg "=== qBittorrent ${QBT_VER} (nox) ==="
  local a="$DL/qbittorrent-${QBT_VER}.tar.gz"
  fetch "$QBT_URL" "$a" "$QBT_SHA256_TGZ"
  rm -rf "$SRC/qbittorrent-${QBT_VER}"
  extract "$a" "$SRC"

  local b="$BUILD/qbittorrent-${QBT_VER}"
  rm -rf "$b"
  cmake_cfg "$SRC/qbittorrent-${QBT_VER}" "$b" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DSTAGING_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGUI=OFF -DWEBUI=ON -DSTACKTRACE=OFF -DTESTING=OFF \
    -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DZLIB_ROOT="$PREFIX"
  cmake_build_install "$b"
}

verify_static() {
  local bin="$PREFIX/bin/qbittorrent-nox"
  [[ -f "$bin" ]] || die "expected binary not found: $bin"

  msg "Verify: file(1) reports statically linked"
  file "$bin" | grep -qi "statically linked" || die "binary is not statically linked"

  msg "Verify: no NEEDED entries"
  if readelf -d "$bin" 2>/dev/null | grep -q 'NEEDED'; then
    readelf -d "$bin" || true
    die "binary has DT_NEEDED entries"
  fi

  if [[ "$STRIP_BIN" == "1" ]]; then
    msg "Strip binary"
    "$STRIP" -s "$bin" || true
  fi

  mkdir -p "$ARTIFACTS_DIR"
  cp -a "$bin" "$ARTIFACTS_DIR/qbittorrent-nox"
  msg "Artifact: $ARTIFACTS_DIR/qbittorrent-nox"
}

msg "Build prefix: $PREFIX"
msg "Downloads cache: $DL"
msg "Host Qt prefix: $HOST_QT_PREFIX"

build_zlib
build_openssl
build_boost
build_libtorrent

fetch_qtbase
build_qtbase_host
build_qtbase_target

fetch_qttools
build_qttools_host
build_qttools_target

build_qbittorrent
verify_static

msg "All done."
