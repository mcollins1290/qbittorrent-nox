#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# build-qbittorrent-nox-static-aarch64-musl
# SCRIPT_VERSION: v0.0.45
#
# Changes vs v0.0.44:
# - Use Boost official release archives/checksums instead of GitHub b2-nodocs assets.
###############################################################################

SCRIPT_NAME="build-qbittorrent-nox-static-aarch64-musl"
SCRIPT_VERSION="v0.0.45"

TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-/opt/gcc-15.3.0-musl-cross}"
TARGET_TRIPLE="${TARGET_TRIPLE:-aarch64-linux-musl}"
SYSROOT="${SYSROOT:-${TOOLCHAIN_ROOT}/${TARGET_TRIPLE}/sysroot}"
TOP="${TOP:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
TOOLCHAIN_FILE="${TOOLCHAIN_FILE:-$TOP/toolchains/aarch64-musl-pi4.cmake}"

HOST_CC="${HOST_CC:-/usr/bin/gcc}"
HOST_CXX="${HOST_CXX:-/usr/bin/g++}"

declare -A PIN_ENV_OVERRIDES=()
for pin_name in LT_VER OPENSSL_VER ZLIB_VER BOOST_VER QT_VER QTBASE_SHA256 QTTOOLS_SHA256 OPENSSL_SHA256 ZLIB_SHA256 LT_SHA256 BOOST_SHA256_TGZ; do
  if [[ -v "$pin_name" ]]; then
    PIN_ENV_OVERRIDES["$pin_name"]="${!pin_name}"
  fi
done
if [[ -v QT_SHA256 ]]; then
  [[ -v QTBASE_SHA256 ]] || PIN_ENV_OVERRIDES["QTBASE_SHA256"]="$QT_SHA256"
  [[ -v QTTOOLS_SHA256 ]] || PIN_ENV_OVERRIDES["QTTOOLS_SHA256"]="$QT_SHA256"
fi
unset pin_name

QBT_VER="${QBT_VER:-latest}"
QBT_TAG="${QBT_TAG:-}"
LT_VER="${LT_VER:-2.0.11}"
OPENSSL_VER="${OPENSSL_VER:-3.5.5}"
ZLIB_VER="${ZLIB_VER:-1.3.2}"
BOOST_VER="${BOOST_VER:-1.91.0}"
QT_VER="${QT_VER:-6.10.3}"

DL="${DL:-$TOP/dl}"
SRC="${SRC:-$TOP/src}"
BUILD="${BUILD:-$TOP/build}"
OUT="${OUT:-$TOP/out}"
PREFIX="${PREFIX:-$OUT/${TARGET_TRIPLE}}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$TOP/artifacts}"
PINS_FILE="${PINS_FILE:-$TOP/dependency-pins.env}"

DEPLOY_HOST="${DEPLOY_HOST:-raspberrypi2.totten}"
DEPLOY_DIR="${DEPLOY_DIR:-/usr/local/bin}"
DEPLOY_SERVICE="${DEPLOY_SERVICE:-qbittorrent-nox.service}"
DEPLOY_RESTART_CMD="${DEPLOY_RESTART_CMD:-systemctl restart ${DEPLOY_SERVICE}}"

JOBS="${JOBS:-$(nproc)}"
STRIP_BIN="${STRIP_BIN:-1}"
ASSUME_YES="${ASSUME_YES:-0}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
TRUST_UNSTAMPED_DEPS="${TRUST_UNSTAMPED_DEPS:-0}"

QTBASE_SHA256="${QTBASE_SHA256:-${QT_SHA256:-}}"
QTTOOLS_SHA256="${QTTOOLS_SHA256:-${QT_SHA256:-}}"
OPENSSL_SHA256="${OPENSSL_SHA256:-}"
ZLIB_SHA256="${ZLIB_SHA256:-}"
LT_SHA256="${LT_SHA256:-}"

QBT_SHA256="${QBT_SHA256:-${QBT_SHA256_TGZ:-}}"
BOOST_SHA256_TGZ="${BOOST_SHA256_TGZ:-5734305f40a76c30f951c9abd409a45a2a19fb546efe4162119250bbe4d3a463}"

# System OpenSSL directory on Debian/RPi OS (config + CA store conventions)
OPENSSL_SYSTEM_DIR="${OPENSSL_SYSTEM_DIR:-/etc/ssl}"

msg() { printf "\n\033[1;36m==>\033[0m %s\n" "$*"; }
die() { printf "\n\033[1;31merror:\033[0m %s\n" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

load_pins_file() {
  local line key value lineno=0
  [[ -f "$PINS_FILE" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^([A-Z0-9_]+)=([A-Za-z0-9._+-]*)$ ]]; then
      die "invalid pins file line ${PINS_FILE}:${lineno}: expected KEY=value"
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "$key" in
      LT_VER|OPENSSL_VER|ZLIB_VER|BOOST_VER|QT_VER|QTBASE_SHA256|QTTOOLS_SHA256|OPENSSL_SHA256|ZLIB_SHA256|LT_SHA256|BOOST_SHA256_TGZ)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        die "invalid pins file key ${PINS_FILE}:${lineno}: ${key}"
        ;;
    esac
  done <"$PINS_FILE"

  for key in "${!PIN_ENV_OVERRIDES[@]}"; do
    printf -v "$key" '%s' "${PIN_ENV_OVERRIDES[$key]}"
  done
  if [[ -v PIN_ENV_OVERRIDES[LT_VER] && ! -v PIN_ENV_OVERRIDES[LT_SHA256] ]]; then
    LT_SHA256=""
  fi
  if [[ -v PIN_ENV_OVERRIDES[OPENSSL_VER] && ! -v PIN_ENV_OVERRIDES[OPENSSL_SHA256] ]]; then
    OPENSSL_SHA256=""
  fi
  if [[ -v PIN_ENV_OVERRIDES[ZLIB_VER] && ! -v PIN_ENV_OVERRIDES[ZLIB_SHA256] ]]; then
    ZLIB_SHA256=""
  fi
  if [[ -v PIN_ENV_OVERRIDES[BOOST_VER] && ! -v PIN_ENV_OVERRIDES[BOOST_SHA256_TGZ] ]]; then
    BOOST_SHA256_TGZ=""
  fi
  if [[ -v PIN_ENV_OVERRIDES[QT_VER] ]]; then
    [[ -v PIN_ENV_OVERRIDES[QTBASE_SHA256] ]] || QTBASE_SHA256=""
    [[ -v PIN_ENV_OVERRIDES[QTTOOLS_SHA256] ]] || QTTOOLS_SHA256=""
  fi
}

load_pins_file

if [[ "$QT_VER" == "6.10.3" ]]; then
  QTBASE_SHA256="${QTBASE_SHA256:-383dc907816338f0cba72088a524c07458dfc69ce684ca9132fcc4fe91c24b0b}"
  QTTOOLS_SHA256="${QTTOOLS_SHA256:-8f00b9e3d1f80973d81cff67684972b89993183ef19924404d5b8ff0f89675b6}"
fi
if [[ "$OPENSSL_VER" == "3.5.5" ]]; then
  OPENSSL_SHA256="${OPENSSL_SHA256:-b28c91532a8b65a1f983b4c28b7488174e4a01008e29ce8e69bd789f28bc2a89}"
fi
if [[ "$ZLIB_VER" == "1.3.2" ]]; then
  ZLIB_SHA256="${ZLIB_SHA256:-d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3}"
fi
if [[ "$LT_VER" == "2.0.11" ]]; then
  LT_SHA256="${LT_SHA256:-f0db58580f4f29ade6cc40fa4ba80e2c9a70c90265cd77332d3cdec37ecf1e6d}"
fi

HOST_QT_PREFIX="${HOST_QT_PREFIX:-$OUT/host-qt-${QT_VER}}"

usage() {
  cat <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION}

Usage:
  $0 [--clean] [--rebuild] [--distclean] [--force-deps] [--qbittorrent-only]
     [--check-updates] [--update-pins] [--deploy] [--deploy-only]
     [--no-strip] [--yes] [--jobs N] [--help]

Modes:
  --check-updates       Report newer dependency releases and exit
  --update-pins         Update pinned dependency versions/sha256 values and exit
  --deploy              Deploy artifact after a successful build and restart service
  --deploy-only         Deploy existing artifact and restart service without building

Environment:
  QBT_VER=latest        Resolve and build the latest qBittorrent GitHub release tag
  QBT_VER=5.1.4         Build a specific qBittorrent release tag
  QBT_TAG=release-5.1.4 Build a specific qBittorrent GitHub tag
  PINS_FILE=path        Dependency pins file to read/update (default: dependency-pins.env)
  ASSUME_YES=1          Start the build without prompting
  SKIP_EXISTING=0       Rebuild prerequisites instead of skipping current stamps
  TRUST_UNSTAMPED_DEPS=1 Treat existing unstamped prerequisite files as reusable
  DEPLOY_HOST=host      SSH host for deployment (default: raspberrypi2.totten)
  DEPLOY_DIR=path       Remote install directory (default: /usr/local/bin)
  DEPLOY_SERVICE=name   Remote systemd service to restart (default: qbittorrent-nox.service)
  DEPLOY_RESTART_CMD=cmd Remote restart command (default: systemctl restart DEPLOY_SERVICE)
EOF
}

assert_rm_rf_safe() {
  local p="$1" abs top_abs
  [[ -n "$p" ]] || die "rm_rf_safe: empty path"
  [[ "$p" != "/" ]] || die "rm_rf_safe: refusing to delete /"
  [[ "$p" != "." ]] || die "rm_rf_safe: refusing to delete ."
  top_abs="$(cd -- "$TOP" && pwd -P)"
  abs="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$p")"
  if [[ "${ALLOW_CLEAN_OUTSIDE_TOP:-0}" != "1" ]]; then
    case "$abs" in
      "$top_abs"/*) ;;
      *) die "refusing to delete outside TOP: $abs (set ALLOW_CLEAN_OUTSIDE_TOP=1 to override)" ;;
    esac
  fi
}

rm_rf_safe() {
  local p="$1"
  assert_rm_rf_safe "$p"
  rm -rf -- "$p"
}

clean() {
  local keep_downloads="${1:-1}"
  if [[ "$keep_downloads" == "1" ]]; then
    msg "Cleaning build outputs (keeping downloads cache: $DL)"
  else
    msg "Cleaning build outputs"
  fi
  assert_rm_rf_safe "$BUILD"
  assert_rm_rf_safe "$SRC"
  assert_rm_rf_safe "$OUT"
  assert_rm_rf_safe "$ARTIFACTS_DIR"
  rm_rf_safe "$BUILD"
  rm_rf_safe "$SRC"
  rm_rf_safe "$OUT"
  rm_rf_safe "$ARTIFACTS_DIR"
}

distclean() {
  msg "Distclean (removing everything including downloads cache: $DL)"
  assert_rm_rf_safe "$DL"
  clean 0
  rm_rf_safe "$DL"
}

sha256_check() {
  local file="$1" expected="$2"
  [[ -z "$expected" ]] && return 0
  echo "${expected}  ${file}" | sha256sum -c -
}

fetch() {
  local url="$1" out="$2" sha="${3:-}" tmp
  mkdir -p "$(dirname "$out")"
  if [[ ! -f "$out" ]]; then
    msg "Downloading: $url"
    tmp="${out}.tmp.$$"
    rm -f -- "$tmp"
    curl -L --fail --retry 3 --retry-delay 2 -o "$tmp" "$url" || {
      rm -f -- "$tmp"
      return 1
    }
    if [[ -n "$sha" ]]; then
      msg "Verifying sha256: $(basename "$out")"
      sha256_check "$tmp" "$sha" || {
        rm -f -- "$tmp"
        return 1
      }
    fi
    mv -f -- "$tmp" "$out"
  else
    msg "Using cached: $out"
    if [[ -n "$sha" ]]; then
      msg "Verifying sha256: $(basename "$out")"
      sha256_check "$out" "$sha"
    fi
  fi
  [[ -n "$sha" ]] || msg "No sha256 provided for $(basename "$out") (skipping verification)"
}

github_release_metadata() {
  local repo="$1" ref="$2" url
  if [[ "$ref" == "latest" ]]; then
    url="https://api.github.com/repos/${repo}/releases/latest"
  else
    url="https://api.github.com/repos/${repo}/releases/tags/${ref}"
  fi
  curl -fsSL "$url"
}

github_release_tag_from_json() {
  python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", ""))'
}

github_asset_sha256_from_json() {
  local asset="$1"
  python3 -c '
import json, sys
asset = sys.argv[1]
for item in json.load(sys.stdin).get("assets", []):
    if item.get("name") == asset:
        digest = item.get("digest") or ""
        if digest.startswith("sha256:"):
            print(digest.split(":", 1)[1])
        break
' "$asset"
}

latest_version_from_github_release() {
  local repo="$1" prefix="${2:-}" tag
  tag="$(github_release_metadata "$repo" latest | github_release_tag_from_json)"
  tag="${tag#"$prefix"}"
  tag="${tag#v}"
  tag="${tag#release-}"
  printf '%s\n' "$tag"
}

latest_version_from_listing() {
  local url="$1" regex="$2" html
  html="$(curl -fsSL "$url")"
  python3 -c '
import re, sys
html = sys.stdin.read()
regex = sys.argv[1]
versions = sorted(
    set(re.findall(regex, html)),
    key=lambda v: tuple(int(p) for p in re.findall(r"\d+", v))
)
print(versions[-1] if versions else "")
' "$regex" <<<"$html"
}

latest_qt_version() {
  local current_major latest_minor
  current_major="${QT_VER%%.*}"
  latest_minor="$(latest_version_from_listing "https://download.qt.io/official_releases/qt/" "(${current_major}\\.[0-9]+)/")"
  [[ -n "$latest_minor" ]] || return 1
  latest_version_from_listing "https://download.qt.io/official_releases/qt/${latest_minor}/" "(${latest_minor}\\.[0-9]+)/"
}

latest_boost_version() {
  latest_version_from_github_release boostorg/boost boost- | python3 -c '
import re, sys
text = sys.stdin.read()
m = re.search(r"([0-9]+\.[0-9]+\.[0-9]+)", text)
print(m.group(1) if m else "")
'
}

boost_version_underscored() {
  printf '%s\n' "$1" | tr . _
}

boost_archive_name() {
  local ver_us
  ver_us="$(boost_version_underscored "$1")"
  printf 'boost_%s.tar.gz\n' "$ver_us"
}

boost_source_dir_name() {
  local ver_us
  ver_us="$(boost_version_underscored "$1")"
  printf 'boost_%s\n' "$ver_us"
}

boost_archive_url() {
  local ver="$1"
  printf 'https://archives.boost.io/release/%s/source/%s\n' "$ver" "$(boost_archive_name "$ver")"
}

boost_release_page_sha256() {
  local ver="$1" archive="$2"
  curl -fsSL "https://www.boost.org/releases/${ver}/" | python3 -c '
import re, sys
archive = re.escape(sys.argv[1])
html = sys.stdin.read()
pattern = archive + r".{0,2000}?title=\"([0-9a-fA-F]{64})\""
m = re.search(pattern, html, re.S)
print(m.group(1).lower() if m else "")
' "$archive"
}

sha256_from_sha256_url() {
  local url="$1"
  curl -fsSL --retry 3 --retry-delay 2 "$url" | python3 -c '
import re, sys
text = sys.stdin.read()
m = re.search(r"\b([0-9a-fA-F]{64})\b", text)
print(m.group(1).lower() if m else "")
'
}

sha256_from_download() {
  local url="$1" tmp sha
  tmp="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.sha256.XXXXXX")"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    rm -f -- "$tmp"
    return 1
  fi
  sha="$(sha256sum "$tmp" | awk '{print $1}')"
  rm -f -- "$tmp"
  printf '%s\n' "$sha"
}

print_update_row() {
  local name="$1" current="$2" latest="$3"
  if [[ -z "$latest" ]]; then
    printf "  %-18s current %-10s latest %-12s %s\n" "$name" "$current" "unknown" "check failed"
  elif [[ "$current" == "latest" ]]; then
    printf "  %-18s current %-10s latest %-12s %s\n" "$name" "$current" "$latest" "configured to resolve latest"
  elif [[ "$latest" == "$current" ]]; then
    printf "  %-18s current %-10s latest %-12s %s\n" "$name" "$current" "$latest" "up to date"
  else
    printf "  %-18s current %-10s latest %-12s %s\n" "$name" "$current" "$latest" "update available"
  fi
}

check_one_update() {
  local name="$1" current="$2" latest=""
  shift 2
  latest="$("$@" 2>/dev/null || true)"
  print_update_row "$name" "$current" "$latest"
}

check_updates() {
  msg "Checking upstream versions (report only)"
  check_one_update "qBittorrent" "$QBT_VER" latest_version_from_github_release qbittorrent/qBittorrent release-
  check_one_update "libtorrent" "$LT_VER" latest_version_from_github_release arvidn/libtorrent v
  check_one_update "Boost" "$BOOST_VER" latest_boost_version
  check_one_update "OpenSSL" "$OPENSSL_VER" latest_version_from_listing https://www.openssl.org/source/ 'openssl-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz'
  check_one_update "zlib" "$ZLIB_VER" latest_version_from_listing https://zlib.net/ 'zlib-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.tar\.(?:gz|xz)'
  check_one_update "Qt" "$QT_VER" latest_qt_version
  msg "No build settings were changed. Run --update-pins to update ${PINS_FILE}."
}

confirm_update_pins() {
  local answer=""
  if [[ "$ASSUME_YES" == "1" ]]; then
    msg "Pin update confirmation skipped (ASSUME_YES=1)."
    return 0
  fi

  printf "\nUpdate pinned dependency versions and sha256 values in %s? [y/N] " "$PINS_FILE"
  if ! read -r answer; then
    die "unable to read update confirmation"
  fi
  case "$answer" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) msg "Pin update aborted."; exit 0 ;;
  esac
}

write_pins_file() {
  local target="$1" tmp
  shift
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  {
    printf '# Dependency pins for %s\n' "$SCRIPT_NAME"
    printf '# This file is data only: KEY=value lines, comments, and blank lines.\n'
    printf '# Update with: ./%s --update-pins\n\n' "$(basename "$0")"
    printf 'LT_VER=%s\n' "$1"
    printf 'LT_SHA256=%s\n\n' "$2"
    printf 'OPENSSL_VER=%s\n' "$3"
    printf 'OPENSSL_SHA256=%s\n\n' "$4"
    printf 'ZLIB_VER=%s\n' "$5"
    printf 'ZLIB_SHA256=%s\n\n' "$6"
    printf 'BOOST_VER=%s\n' "$7"
    printf 'BOOST_SHA256_TGZ=%s\n\n' "$8"
    printf 'QT_VER=%s\n' "$9"
    shift 9
    printf 'QTBASE_SHA256=%s\n' "$1"
    printf 'QTTOOLS_SHA256=%s\n' "$2"
  } >"$tmp"
  mv -f -- "$tmp" "$target"
}

update_pins() {
  local lt_json lt_ver lt_sha
  local openssl_ver openssl_sha
  local zlib_ver zlib_sha
  local qt_ver qtbase_sha qttools_sha
  local boost_ver boost_archive boost_sha

  msg "Resolving latest supported dependency pins"

  lt_json="$(github_release_metadata arvidn/libtorrent latest)"
  lt_ver="$(printf '%s\n' "$lt_json" | github_release_tag_from_json)"
  lt_ver="${lt_ver#v}"
  lt_sha="$(printf '%s\n' "$lt_json" | github_asset_sha256_from_json "libtorrent-rasterbar-${lt_ver}.tar.gz")"
  [[ -n "$lt_ver" && -n "$lt_sha" ]] || die "unable to resolve libtorrent version/sha256"

  openssl_ver="$(latest_version_from_listing https://www.openssl.org/source/ 'openssl-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz')"
  openssl_sha="$(sha256_from_sha256_url "https://www.openssl.org/source/openssl-${openssl_ver}.tar.gz.sha256")"
  [[ -n "$openssl_ver" && -n "$openssl_sha" ]] || die "unable to resolve OpenSSL version/sha256"

  zlib_ver="$(latest_version_from_listing https://zlib.net/ 'zlib-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.tar\.xz')"
  zlib_sha="$(sha256_from_download "https://zlib.net/zlib-${zlib_ver}.tar.xz")"
  [[ -n "$zlib_ver" && -n "$zlib_sha" ]] || die "unable to resolve zlib version/sha256"

  qt_ver="$(latest_qt_version)"
  qtbase_sha="$(sha256_from_sha256_url "https://download.qt.io/official_releases/qt/${qt_ver%.*}/${qt_ver}/submodules/qtbase-everywhere-src-${qt_ver}.tar.xz.sha256")"
  qttools_sha="$(sha256_from_sha256_url "https://download.qt.io/official_releases/qt/${qt_ver%.*}/${qt_ver}/submodules/qttools-everywhere-src-${qt_ver}.tar.xz.sha256")"
  [[ -n "$qt_ver" && -n "$qtbase_sha" && -n "$qttools_sha" ]] || die "unable to resolve Qt version/sha256"

  boost_ver="$(latest_boost_version)"
  boost_archive="$(boost_archive_name "$boost_ver")"
  boost_sha="$(boost_release_page_sha256 "$boost_ver" "$boost_archive")"
  [[ -n "$boost_ver" && -n "$boost_sha" ]] || die "unable to resolve Boost version/sha256"

  msg "Resolved pins"
  printf "  libtorrent:  %s  %s\n" "$lt_ver" "$lt_sha"
  printf "  OpenSSL:     %s  %s\n" "$openssl_ver" "$openssl_sha"
  printf "  zlib:        %s  %s\n" "$zlib_ver" "$zlib_sha"
  printf "  QtBase:      %s  %s\n" "$qt_ver" "$qtbase_sha"
  printf "  QtTools:     %s  %s\n" "$qt_ver" "$qttools_sha"
  printf "  Boost:       %s  %s\n" "$boost_ver" "$boost_sha"

  confirm_update_pins

  write_pins_file "$PINS_FILE" \
    "$lt_ver" "$lt_sha" \
    "$openssl_ver" "$openssl_sha" \
    "$zlib_ver" "$zlib_sha" \
    "$boost_ver" "$boost_sha" \
    "$qt_ver" "$qtbase_sha" "$qttools_sha"

  msg "Updated pinned dependency versions in $PINS_FILE"
  msg "Run: git diff -- $PINS_FILE"
}

resolve_qbittorrent_version() {
  local release_json="" source_asset=""
  if [[ -z "$QBT_TAG" ]]; then
    if [[ "$QBT_VER" == "latest" ]]; then
      msg "Resolving latest qBittorrent release tag from GitHub"
      release_json="$(github_release_metadata qbittorrent/qBittorrent latest)"
      QBT_TAG="$(printf '%s\n' "$release_json" | github_release_tag_from_json)"
      [[ -n "$QBT_TAG" ]] || die "unable to resolve latest GitHub release tag for qbittorrent/qBittorrent"
    else
      QBT_TAG="release-${QBT_VER#release-}"
    fi
  fi

  QBT_VER="${QBT_TAG#release-}"
  QBT_URL="https://github.com/qbittorrent/qBittorrent/releases/download/${QBT_TAG}/qbittorrent-${QBT_VER}.tar.xz"
  source_asset="qbittorrent-${QBT_VER}.tar.xz"

  if [[ -z "$QBT_SHA256" ]]; then
    if [[ -z "$release_json" ]]; then
      release_json="$(github_release_metadata qbittorrent/qBittorrent "$QBT_TAG")"
    fi
    QBT_SHA256="$(printf '%s\n' "$release_json" | github_asset_sha256_from_json "$source_asset")"
    if [[ -n "$QBT_SHA256" ]]; then
      msg "qBittorrent source sha256: ${QBT_SHA256}"
    else
      msg "No GitHub sha256 digest found for ${source_asset} (skipping verification)"
    fi
  fi
}

show_build_summary() {
  msg "Build summary"
  printf "  qBittorrent: %s (%s)\n" "$QBT_VER" "$QBT_TAG"
  printf "  libtorrent:  %s\n" "$LT_VER"
  printf "  Qt:          %s\n" "$QT_VER"
  printf "  OpenSSL:     %s\n" "$OPENSSL_VER"
  printf "  Boost:       %s\n" "$BOOST_VER"
  printf "  zlib:        %s\n" "$ZLIB_VER"
  printf "  Target:      %s\n" "$TARGET_TRIPLE"
  printf "  Prefix:      %s\n" "$PREFIX"
  printf "  Jobs:        %s\n" "$JOBS"
}

extract() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  msg "Extract: $(basename "$archive")"
  tar --no-same-owner --no-same-permissions -xf "$archive" -C "$dest"
}

cmake_cfg() {
  local src_dir="$1" build_dir="$2"
  shift 2
  cmake -G Ninja -S "$src_dir" -B "$build_dir" \
    -DTOOLCHAIN_ROOT="$TOOLCHAIN_ROOT" \
    -DTARGET_TRIPLE="$TARGET_TRIPLE" \
    -DSYSROOT="$SYSROOT" \
    "$@"
}

cmake_build_install() {
  local build_dir="$1"
  cmake --build "$build_dir" --parallel "$JOBS"
  cmake --install "$build_dir"
}

confirm_deploy() {
  local answer=""
  if [[ "$ASSUME_YES" == "1" ]]; then
    msg "Deploy confirmation skipped (ASSUME_YES=1)."
    return 0
  fi

  printf "\nDeploy %s/qbittorrent-nox to %s:%s and run '%s'? [y/N] " \
    "$ARTIFACTS_DIR" "$DEPLOY_HOST" "$DEPLOY_DIR" "$DEPLOY_RESTART_CMD"
  if ! read -r answer; then
    die "unable to read deploy confirmation"
  fi

  case "$answer" in
    [Yy]|[Yy][Ee][Ss]) ;;
    *) msg "Deploy aborted."; exit 0 ;;
  esac
}

deploy_artifact() {
  local artifact="$ARTIFACTS_DIR/qbittorrent-nox"
  local local_sha remote_path remote_sha
  local require_confirm="${1:-1}"
  [[ -f "$artifact" ]] || die "artifact not found: $artifact"

  need rsync
  need ssh
  need sha256sum
  if [[ "$require_confirm" == "1" ]]; then
    confirm_deploy
  fi

  msg "Deploy: $artifact -> ${DEPLOY_HOST}:${DEPLOY_DIR}/"
  rsync -aAX "$artifact" "${DEPLOY_HOST}:${DEPLOY_DIR}/"

  local_sha="$(sha256sum "$artifact" | awk '{print $1}')"
  remote_path="${DEPLOY_DIR%/}/qbittorrent-nox"
  msg "Verify deployed artifact sha256"
  # shellcheck disable=SC2029 # remote_path is intentionally expanded locally.
  remote_sha="$(ssh "$DEPLOY_HOST" "sha256sum '$remote_path' | awk '{print \$1}'")"
  [[ -n "$remote_sha" ]] || die "unable to read deployed artifact sha256: ${DEPLOY_HOST}:${remote_path}"
  if [[ "$remote_sha" != "$local_sha" ]]; then
    die "deployed artifact sha256 mismatch: local ${local_sha}, remote ${remote_sha}"
  fi

  msg "Restart remote service: ${DEPLOY_SERVICE}"
  # shellcheck disable=SC2029 # DEPLOY_RESTART_CMD is intentionally expanded locally.
  ssh "$DEPLOY_HOST" "$DEPLOY_RESTART_CMD"
}

offer_deploy_after_build() {
  local answer=""
  [[ "$DO_DEPLOY" == "0" ]] || return 0
  [[ "$ASSUME_YES" == "0" ]] || return 0

  printf "\nBuild completed successfully. Deploy %s/qbittorrent-nox to %s:%s and restart %s? [y/N] " \
    "$ARTIFACTS_DIR" "$DEPLOY_HOST" "$DEPLOY_DIR" "$DEPLOY_SERVICE"
  if ! read -r answer; then
    die "unable to read deploy selection"
  fi

  case "$answer" in
    [Yy]|[Yy][Ee][Ss])
      deploy_artifact 0
      ;;
    *)
      msg "Deploy skipped."
      ;;
  esac
}

ORIGINAL_ARGC=$#
DO_CLEAN=0
DO_REBUILD=0
DO_DISTCLEAN=0
DO_QBT_ONLY=0
DO_CLEAN_BEFORE_BUILD=0
DO_CHECK_UPDATES=0
DO_UPDATE_PINS=0
DO_DEPLOY=0
DO_DEPLOY_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) DO_CLEAN=1; shift ;;
    --rebuild) DO_REBUILD=1; shift ;;
    --distclean) DO_DISTCLEAN=1; shift ;;
    --force-deps) SKIP_EXISTING=0; shift ;;
    --qbittorrent-only) DO_QBT_ONLY=1; shift ;;
    --check-updates) DO_CHECK_UPDATES=1; shift ;;
    --update-pins) DO_UPDATE_PINS=1; shift ;;
    --deploy) DO_DEPLOY=1; shift ;;
    --deploy-only) DO_DEPLOY=1; DO_DEPLOY_ONLY=1; shift ;;
    --no-strip) STRIP_BIN=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --jobs) shift; [[ $# -gt 0 ]] || die "--jobs requires a value"; JOBS="$1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ "$DO_REBUILD" == "1" ]]; then DO_CLEAN=1; fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"

msg "${SCRIPT_NAME} ${SCRIPT_VERSION}"
msg "Host: $(uname -a)"
msg "Target: ${TARGET_TRIPLE}"
msg "Toolchain root: ${TOOLCHAIN_ROOT}"
msg "Sysroot: ${SYSROOT}"
msg "Toolchain file: ${TOOLCHAIN_FILE}"
msg "Pins file: ${PINS_FILE}"
msg "Jobs: ${JOBS}"
msg "Strip: ${STRIP_BIN}"
msg "OpenSSL OPENSSLDIR: ${OPENSSL_SYSTEM_DIR}"
if [[ "$DO_DEPLOY" == "1" ]]; then
  msg "Deploy target: ${DEPLOY_HOST}:${DEPLOY_DIR}"
  msg "Deploy restart: ${DEPLOY_RESTART_CMD}"
fi

need python3

if [[ "$DO_DEPLOY_ONLY" == "1" ]]; then
  deploy_artifact
  msg "Deploy complete."
  exit 0
fi

if [[ "$DO_CHECK_UPDATES" == "1" ]]; then
  need curl
  check_updates
  exit 0
fi

if [[ "$DO_UPDATE_PINS" == "1" ]]; then
  need curl
  need sha256sum
  update_pins
  exit 0
fi

if [[ "$DO_DISTCLEAN" == "1" && "$DO_REBUILD" != "1" ]]; then
  distclean
  msg "Distclean complete."
  exit 0
fi

if [[ "$DO_CLEAN" == "1" && "$DO_REBUILD" != "1" ]]; then
  clean
  msg "Clean complete."
  exit 0
fi

need curl
need tar; need cmake; need ninja; need perl; need pkg-config; need make
need g++; need file; need readelf; need sha256sum

[[ -x "${TOOLCHAIN_ROOT}/bin/${TARGET_TRIPLE}-gcc" ]] || die "cross gcc not found"
[[ -d "$SYSROOT" ]] || die "SYSROOT not found: $SYSROOT"
[[ -f "$TOOLCHAIN_FILE" ]] || die "TOOLCHAIN_FILE not found: $TOOLCHAIN_FILE"
[[ -x "$HOST_CC" ]] || die "HOST_CC not executable: $HOST_CC"
[[ -x "$HOST_CXX" ]] || die "HOST_CXX not executable: $HOST_CXX"

resolve_qbittorrent_version
msg "qBittorrent tag: ${QBT_TAG}"
show_build_summary

if [[ "$DO_DISTCLEAN" == "1" ]]; then
  distclean
elif [[ "$DO_CLEAN" == "1" ]]; then
  clean
fi

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
BOOST_URL="$(boost_archive_url "$BOOST_VER")"
LT_URL="https://github.com/arvidn/libtorrent/releases/download/v${LT_VER}/libtorrent-rasterbar-${LT_VER}.tar.gz"

QTBASE_URL="https://download.qt.io/official_releases/qt/${QT_VER%.*}/${QT_VER}/submodules/qtbase-everywhere-src-${QT_VER}.tar.xz"
QTTOOLS_URL="https://download.qt.io/official_releases/qt/${QT_VER%.*}/${QT_VER}/submodules/qttools-everywhere-src-${QT_VER}.tar.xz"

STAMP_DIR="$PREFIX/.build-stamps"
HOST_QT_STAMP_DIR="$HOST_QT_PREFIX/.build-stamps"
MISSING_DEPS=()
UNSTAMPED_DEPS=()
VERSION_CHANGED_DEPS=()
STALE_STAMP_DEPS=()
CASCADE_REBUILD_DEPS=()
declare -A FORCE_BUILD_DEPS=()

stamp_file() {
  local stamp_dir="$1" name="$2" ver="$3"
  printf '%s/%s-%s.stamp' "$stamp_dir" "$name" "$ver"
}

write_build_stamp() {
  local stamp_dir="$1" name="$2" ver="$3" stamp tmp
  mkdir -p "$stamp_dir"
  stamp="$(stamp_file "$stamp_dir" "$name" "$ver")"
  tmp="${stamp}.tmp.$$"
  stamp_content "$name" "$ver" >"$tmp"
  mv -f -- "$tmp" "$stamp"
}

stamp_content() {
  local name="$1" ver="$2"
  printf 'stamp_schema=2\n'
  printf 'name=%s\n' "$name"
  printf 'version=%s\n' "$ver"
  printf 'target=%s\n' "$TARGET_TRIPLE"
  printf 'script=%s\n' "$SCRIPT_VERSION"
  printf 'toolchain_root=%s\n' "$TOOLCHAIN_ROOT"
  printf 'target_triple=%s\n' "$TARGET_TRIPLE"
  printf 'sysroot=%s\n' "$SYSROOT"
  printf 'toolchain_file=%s\n' "$TOOLCHAIN_FILE"
  printf 'host_cc=%s\n' "$HOST_CC"
  printf 'host_cxx=%s\n' "$HOST_CXX"
  printf 'cflags=%s\n' "$CFLAGS"
  printf 'cxxflags=%s\n' "$CXXFLAGS"
  printf 'ldflags=%s\n' "$LDFLAGS"
  printf 'openssl_system_dir=%s\n' "$OPENSSL_SYSTEM_DIR"
  printf 'zlib_ver=%s\n' "$ZLIB_VER"
  printf 'openssl_ver=%s\n' "$OPENSSL_VER"
  printf 'boost_ver=%s\n' "$BOOST_VER"
  printf 'libtorrent_ver=%s\n' "$LT_VER"
  printf 'qt_ver=%s\n' "$QT_VER"
}

have_files() {
  local f
  for f in "$@"; do
    [[ -e "$f" ]] || return 1
  done
}

dep_files() {
  case "$1" in
    zlib)
      printf '%s\n' "$PREFIX/lib/libz.a" "$PREFIX/include/zlib.h"
      ;;
    openssl)
      printf '%s\n' "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a" "$PREFIX/include/openssl/ssl.h"
      ;;
    boost)
      printf '%s\n' \
        "$PREFIX/include/boost/version.hpp" \
        "$PREFIX/lib/cmake/Boost-${BOOST_VER}/BoostConfig.cmake" \
        "$PREFIX/lib/libboost_filesystem.a" \
        "$PREFIX/lib/libboost_program_options.a"
      ;;
    libtorrent)
      printf '%s\n' "$PREFIX/lib/libtorrent-rasterbar.a" "$PREFIX/include/libtorrent/version.hpp"
      ;;
    qtbase-host)
      printf '%s\n' "$HOST_QT_PREFIX/bin/qt-cmake" "$HOST_QT_PREFIX/lib/cmake/Qt6/Qt6Config.cmake"
      ;;
    qtbase-target)
      printf '%s\n' "$PREFIX/lib/libQt6Core.a" "$PREFIX/lib/libQt6Network.a" "$PREFIX/lib/cmake/Qt6/Qt6Config.cmake"
      ;;
    qttools-host)
      printf '%s\n' "$HOST_QT_PREFIX/bin/lrelease"
      ;;
    qttools-target)
      printf '%s\n' "$PREFIX/lib/cmake/Qt6Linguist/Qt6LinguistConfig.cmake" "$PREFIX/lib/cmake/Qt6Tools/Qt6ToolsConfig.cmake"
      ;;
    *)
      die "unknown dependency file set: $1"
      ;;
  esac
}

dep_stamp_dir() {
  case "$1" in
    qtbase-host|qttools-host) printf '%s\n' "$HOST_QT_STAMP_DIR" ;;
    *) printf '%s\n' "$STAMP_DIR" ;;
  esac
}

dep_version() {
  case "$1" in
    zlib) printf '%s\n' "$ZLIB_VER" ;;
    openssl) printf '%s\n' "$OPENSSL_VER" ;;
    boost) printf '%s\n' "$BOOST_VER" ;;
    libtorrent) printf '%s\n' "$LT_VER" ;;
    qtbase-host|qtbase-target|qttools-host|qttools-target) printf '%s\n' "$QT_VER" ;;
    *) die "unknown dependency version: $1" ;;
  esac
}

dep_label() {
  case "$1" in
    zlib) printf 'zlib' ;;
    openssl) printf 'OpenSSL' ;;
    boost) printf 'Boost' ;;
    libtorrent) printf 'libtorrent-rasterbar' ;;
    qtbase-host) printf 'QtBase host' ;;
    qtbase-target) printf 'QtBase target' ;;
    qttools-host) printf 'QtTools host' ;;
    qttools-target) printf 'QtTools target' ;;
    *) die "unknown dependency label: $1" ;;
  esac
}

dep_has_files() {
  local dep="$1"
  local -a files=()
  mapfile -t files < <(dep_files "$dep")
  have_files "${files[@]}"
}

dep_has_stamp() {
  local dep="$1" ver stamp_dir
  ver="$(dep_version "$dep")"
  stamp_dir="$(dep_stamp_dir "$dep")"
  [[ -f "$(stamp_file "$stamp_dir" "$dep" "$ver")" ]]
}

dep_stamp_matches_identity() {
  local dep="$1" ver stamp_dir stamp tmp
  ver="$(dep_version "$dep")"
  stamp_dir="$(dep_stamp_dir "$dep")"
  stamp="$(stamp_file "$stamp_dir" "$dep" "$ver")"
  [[ -f "$stamp" ]] || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.stamp.XXXXXX")"
  stamp_content "$dep" "$ver" >"$tmp"
  if cmp -s "$tmp" "$stamp"; then
    rm -f -- "$tmp"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

dep_has_other_version_stamp() {
  local dep="$1" ver stamp_dir stamp
  local -a stamps=()
  ver="$(dep_version "$dep")"
  stamp_dir="$(dep_stamp_dir "$dep")"
  [[ -d "$stamp_dir" ]] || return 1

  shopt -s nullglob
  stamps=("$stamp_dir/${dep}-"*.stamp)
  shopt -u nullglob

  for stamp in "${stamps[@]}"; do
    [[ "$stamp" == "$(stamp_file "$stamp_dir" "$dep" "$ver")" ]] && continue
    return 0
  done
  return 1
}

dep_is_current() {
  local dep="$1"
  dep_has_files "$dep" && dep_stamp_matches_identity "$dep"
}

dep_is_reusable() {
  local dep="$1"
  dep_is_current "$dep" && return 0
  [[ "$TRUST_UNSTAMPED_DEPS" == "1" ]] && dep_has_files "$dep"
}

dep_needs_build() {
  local dep="$1"
  [[ "$SKIP_EXISTING" == "1" ]] || return 0
  [[ -n "${FORCE_BUILD_DEPS[$dep]:-}" ]] && return 0
  dep_is_reusable "$dep" && return 1
  return 0
}

collect_dependency_status() {
  local dep
  MISSING_DEPS=()
  UNSTAMPED_DEPS=()
  VERSION_CHANGED_DEPS=()
  STALE_STAMP_DEPS=()
  for dep in zlib openssl boost libtorrent qtbase-host qtbase-target qttools-host qttools-target; do
    if dep_has_other_version_stamp "$dep"; then
      VERSION_CHANGED_DEPS+=("$dep")
    elif ! dep_has_files "$dep"; then
      MISSING_DEPS+=("$dep")
    elif ! dep_has_stamp "$dep"; then
      UNSTAMPED_DEPS+=("$dep")
    elif ! dep_stamp_matches_identity "$dep"; then
      STALE_STAMP_DEPS+=("$dep")
    fi
  done
}

show_dependency_report() {
  local dep label ver status
  collect_dependency_status
  msg "Prerequisite status"
  for dep in zlib openssl boost libtorrent qtbase-host qtbase-target qttools-host qttools-target; do
    label="$(dep_label "$dep")"
    ver="$(dep_version "$dep")"
    if dep_has_other_version_stamp "$dep"; then
      status="different stamped version present; clean rebuild required"
    elif dep_has_files "$dep" && dep_has_stamp "$dep" && ! dep_stamp_matches_identity "$dep"; then
      status="stamp identity changed; clean rebuild required"
    elif [[ "$DO_QBT_ONLY" == "1" ]]; then
      if dep_has_files "$dep"; then
        if dep_stamp_matches_identity "$dep"; then
          status="available"
        else
          status="not current; qBittorrent-only cannot proceed"
        fi
      else
        status="missing; qBittorrent-only cannot proceed"
      fi
    elif [[ "$SKIP_EXISTING" != "1" ]]; then
      if dep_has_files "$dep"; then
        status="available; will rebuild"
      else
        status="missing; will build"
      fi
    elif dep_is_current "$dep"; then
      status="current; will skip"
    elif dep_has_files "$dep"; then
      if [[ "$TRUST_UNSTAMPED_DEPS" == "1" ]]; then
        status="files present, no stamp; will trust and skip"
      else
        status="files present, no stamp; will rebuild once"
      fi
    else
      status="missing; will build"
    fi
    printf "  %-22s %-8s %s\n" "$label" "$ver" "$status"
  done

  if ((${#VERSION_CHANGED_DEPS[@]} > 0 || ${#STALE_STAMP_DEPS[@]} > 0)); then
    printf "  qBittorrent-only:     not possible; dependency stamp mismatch requires clean rebuild\n"
  elif deps_all_current; then
    printf "  qBittorrent-only:     possible; prerequisites are current\n"
  else
    printf "  qBittorrent-only:     not possible; prerequisites are missing or not current\n"
  fi
}

deps_all_current() {
  local dep
  for dep in zlib openssl boost libtorrent qtbase-host qtbase-target qttools-host qttools-target; do
    dep_is_current "$dep" || return 1
  done
}

deps_need_clean_rebuild() {
  collect_dependency_status
  ((${#VERSION_CHANGED_DEPS[@]} > 0 || ${#STALE_STAMP_DEPS[@]} > 0))
}

recommended_build_mode() {
  if deps_need_clean_rebuild; then
    printf '3'
  elif deps_all_current; then
    printf '2'
  else
    printf '1'
  fi
}

choose_default_build_mode() {
  local answer="" default_choice
  [[ "$ORIGINAL_ARGC" == "0" ]] || return 0
  [[ "$ASSUME_YES" == "1" ]] && return 0
  default_choice="$(recommended_build_mode)"

  printf "\nChoose how to proceed:\n"
  printf "  1) Quickest safe build: skip current stamped prerequisites, rebuild missing/unstamped ones, then build qBittorrent\n"
  printf "  2) qBittorrent only: require current stamped prerequisites\n"
  printf "  3) Clean rebuild: remove build/src/out/artifacts, rebuild prerequisites, then build qBittorrent\n"
  printf "  4) Abort\n"
  printf "Selection [%s]: " "$default_choice"
  if ! read -r answer; then
    die "unable to read build selection"
  fi
  answer="${answer:-$default_choice}"

  case "$answer" in
    1)
      ;;
    2)
      DO_QBT_ONLY=1
      ;;
    3)
      SKIP_EXISTING=0
      DO_CLEAN_BEFORE_BUILD=1
      ;;
    4|[Aa]|[Aa][Bb][Oo][Rr][Tt])
      msg "Build aborted."
      exit 0
      ;;
    *)
      die "unknown selection: $answer"
      ;;
  esac
}

prepare_clean_rebuild_if_needed() {
  if deps_need_clean_rebuild; then
    if [[ "$DO_QBT_ONLY" == "1" ]]; then
      show_dependency_report
      die "--qbittorrent-only requested, but dependency stamp mismatch requires a clean rebuild"
    fi
    DO_CLEAN_BEFORE_BUILD=1
    SKIP_EXISTING=0
    msg "Dependency stamp mismatch detected; forcing a clean rebuild"
  fi

  if [[ "$DO_CLEAN_BEFORE_BUILD" == "1" ]]; then
    clean
    mkdir -p "$DL" "$SRC" "$BUILD" "$OUT" "$PREFIX" "$ARTIFACTS_DIR" "$HOST_QT_PREFIX"
  fi
}

mark_dep_for_rebuild() {
  local dep="$1"
  if [[ -z "${FORCE_BUILD_DEPS[$dep]:-}" ]]; then
    FORCE_BUILD_DEPS["$dep"]=1
    CASCADE_REBUILD_DEPS+=("$dep")
  fi
}

dep_planned_for_build() {
  local dep="$1"
  [[ -n "${FORCE_BUILD_DEPS[$dep]:-}" ]]
}

plan_dependency_rebuilds() {
  local dep changed=1
  FORCE_BUILD_DEPS=()
  CASCADE_REBUILD_DEPS=()

  if [[ "$SKIP_EXISTING" != "1" ]]; then
    return 0
  fi

  for dep in zlib openssl boost libtorrent qtbase-host qtbase-target qttools-host qttools-target; do
    if dep_needs_build "$dep"; then
      mark_dep_for_rebuild "$dep"
    fi
  done

  while [[ "$changed" == "1" ]]; do
    changed=0
    if dep_planned_for_build zlib || dep_planned_for_build openssl; then
      for dep in libtorrent qtbase-target qttools-target; do
        if [[ -z "${FORCE_BUILD_DEPS[$dep]:-}" ]]; then
          mark_dep_for_rebuild "$dep"
          changed=1
        fi
      done
    fi
    if dep_planned_for_build boost; then
      if [[ -z "${FORCE_BUILD_DEPS[libtorrent]:-}" ]]; then
        mark_dep_for_rebuild libtorrent
        changed=1
      fi
    fi
    if dep_planned_for_build qtbase-host; then
      for dep in qtbase-target qttools-host qttools-target; do
        if [[ -z "${FORCE_BUILD_DEPS[$dep]:-}" ]]; then
          mark_dep_for_rebuild "$dep"
          changed=1
        fi
      done
    fi
    if dep_planned_for_build qtbase-target || dep_planned_for_build qttools-host; then
      if [[ -z "${FORCE_BUILD_DEPS[qttools-target]:-}" ]]; then
        mark_dep_for_rebuild qttools-target
        changed=1
      fi
    fi
  done
}

show_cascade_rebuild_report() {
  local dep
  ((${#CASCADE_REBUILD_DEPS[@]} > 0)) || return 0
  msg "Prerequisites selected for rebuild"
  for dep in "${CASCADE_REBUILD_DEPS[@]}"; do
    printf "  %s\n" "$(dep_label "$dep")"
  done
}

confirm_build_plan() {
  local answer=""
  if [[ "$ASSUME_YES" == "1" || "$ORIGINAL_ARGC" == "0" ]]; then
    [[ "$ASSUME_YES" == "1" ]] && msg "Build confirmation skipped (ASSUME_YES=1)."
    return 0
  fi

  printf "\nAbout to build qBittorrent %s (%s).\n" "$QBT_VER" "$QBT_TAG"
  printf "Start build? [Y/n] "
  if ! read -r answer; then
    die "unable to read build confirmation"
  fi

  case "$answer" in
    ""|[Yy]|[Yy][Ee][Ss]) ;;
    *) msg "Build aborted."; exit 0 ;;
  esac
}

build_zlib() {
  msg "=== zlib ${ZLIB_VER} (static, non-CMake) ==="
  local a="$DL/zlib-${ZLIB_VER}.tar.xz"
  fetch "$ZLIB_URL" "$a" "$ZLIB_SHA256"
  rm_rf_safe "$SRC/zlib-${ZLIB_VER}"
  extract "$a" "$SRC"

  pushd "$SRC/zlib-${ZLIB_VER}" >/dev/null
  rm -f Makefile configure.log
  msg "Configure zlib (static)"
  CHOST="$TARGET_TRIPLE" CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS" \
    ./configure --static --prefix="$PREFIX"
  msg "Build zlib"; make -j"$JOBS"
  msg "Install zlib"; make install
  popd >/dev/null
  write_build_stamp "$STAMP_DIR" zlib "$ZLIB_VER"
}

build_openssl() {
  msg "=== OpenSSL ${OPENSSL_VER} ==="
  local a="$DL/openssl-${OPENSSL_VER}.tar.gz"
  local cflags_arr=() lflags_arr=()
  fetch "$OPENSSL_URL" "$a" "$OPENSSL_SHA256"
  rm_rf_safe "$SRC/openssl-${OPENSSL_VER}"
  extract "$a" "$SRC"

  pushd "$SRC/openssl-${OPENSSL_VER}" >/dev/null
  make clean >/dev/null 2>&1 || true

  msg "Configure OpenSSL (static, OPENSSLDIR=${OPENSSL_SYSTEM_DIR})"
  read -r -a cflags_arr <<< "$CFLAGS"
  read -r -a lflags_arr <<< "$LDFLAGS"
  ./Configure linux-aarch64 no-shared no-tests no-legacy \
    --prefix="$PREFIX" --openssldir="${OPENSSL_SYSTEM_DIR}" -static \
    "${cflags_arr[@]}" "${lflags_arr[@]}"

  msg "Build OpenSSL"; make -j"$JOBS"
  msg "Install OpenSSL"; make install_sw
  popd >/dev/null
  write_build_stamp "$STAMP_DIR" openssl "$OPENSSL_VER"
}

build_boost() {
  msg "=== Boost ${BOOST_VER} ==="
  local archive srcdir
  archive="$(boost_archive_name "$BOOST_VER")"
  srcdir="$SRC/$(boost_source_dir_name "$BOOST_VER")"
  local a="$DL/$archive"
  fetch "$BOOST_URL" "$a" "$BOOST_SHA256_TGZ"
  rm_rf_safe "$srcdir"
  extract "$a" "$SRC"

  pushd "$srcdir" >/dev/null
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
    --with-chrono --with-date_time --with-random --with-atomic --with-thread \
    --with-regex --with-filesystem --with-program_options \
    install
  popd >/dev/null
  write_build_stamp "$STAMP_DIR" boost "$BOOST_VER"
}

apply_libtorrent_openssl4_patch() {
  local srcdir="$1"
  [[ "${OPENSSL_VER%%.*}" -ge 4 ]] || return 0

  msg "Patch libtorrent for OpenSSL ${OPENSSL_VER} ASN.1 accessors"
  python3 - "$srcdir/src/torrent.cpp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        "\t\t\tGENERAL_NAME* gen = sk_GENERAL_NAME_value(gens, i);",
        "\t\t\tGENERAL_NAME const* gen = sk_GENERAL_NAME_value(gens, i);",
    ),
    (
        "\t\t\tASN1_IA5STRING* domain = gen->d.dNSName;",
        "\t\t\tASN1_IA5STRING const* domain = gen->d.dNSName;",
    ),
    (
        "\t\t\tif (domain->type != V_ASN1_IA5STRING || !domain->data || !domain->length) continue;",
        "\t\t\tif (ASN1_STRING_type(domain) != V_ASN1_IA5STRING || !ASN1_STRING_get0_data(domain)\n"
        "\t\t\t\t|| ASN1_STRING_length(domain) <= 0) continue;",
    ),
    (
        "\t\t\tauto const* torrent_name = reinterpret_cast<char const*>(domain->data);",
        "\t\t\tauto const* torrent_name = reinterpret_cast<char const*>(ASN1_STRING_get0_data(domain));",
    ),
    (
        "\t\t\tauto const name_length = aux::numeric_cast<std::size_t>(domain->length);",
        "\t\t\tauto const name_length = aux::numeric_cast<std::size_t>(ASN1_STRING_length(domain));",
    ),
    (
        "\t\tX509_NAME* name = X509_get_subject_name(cert);",
        "\t\tX509_NAME const* name = X509_get_subject_name(cert);",
    ),
    (
        "\t\tASN1_STRING* common_name = nullptr;",
        "\t\tASN1_STRING const* common_name = nullptr;",
    ),
    (
        "\t\t\tX509_NAME_ENTRY* name_entry = X509_NAME_get_entry(name, i);",
        "\t\t\tX509_NAME_ENTRY const* name_entry = X509_NAME_get_entry(name, i);",
    ),
    (
        "\t\tif (common_name && common_name->data && common_name->length)",
        "\t\tif (common_name && ASN1_STRING_get0_data(common_name) && ASN1_STRING_length(common_name) > 0)",
    ),
    (
        "\t\t\tauto const* torrent_name = reinterpret_cast<char const*>(common_name->data);",
        "\t\t\tauto const* torrent_name = reinterpret_cast<char const*>(ASN1_STRING_get0_data(common_name));",
    ),
    (
        "\t\t\tauto const name_length = aux::numeric_cast<std::size_t>(common_name->length);",
        "\t\t\tauto const name_length = aux::numeric_cast<std::size_t>(ASN1_STRING_length(common_name));",
    ),
]

for old_text, new_text in replacements:
    text = text.replace(old_text, new_text)

required = [
    "GENERAL_NAME const* gen = sk_GENERAL_NAME_value(gens, i);",
    "ASN1_IA5STRING const* domain = gen->d.dNSName;",
    "ASN1_STRING_get0_data(domain)",
    "ASN1_STRING_length(domain)",
    "ASN1_STRING const* common_name = nullptr;",
    "X509_NAME_ENTRY const* name_entry = X509_NAME_get_entry(name, i);",
    "ASN1_STRING_get0_data(common_name)",
    "ASN1_STRING_length(common_name)",
]
for needle in required:
    if needle not in text:
        sys.exit(f"unable to patch libtorrent OpenSSL handling: missing {needle}")

for forbidden in ["domain->data", "domain->length", "common_name->data", "common_name->length"]:
    if forbidden in text:
        sys.exit(f"unable to patch libtorrent OpenSSL handling: still found {forbidden}")

path.write_text(text)
PY
}

apply_qtbase_openssl4_patch() {
  local srcdir="$1"
  [[ "${OPENSSL_VER%%.*}" -ge 4 ]] || return 0

  msg "Patch QtBase for OpenSSL ${OPENSSL_VER} ASN.1 accessors"
  python3 - "$srcdir/src/plugins/tls/openssl/qx509_openssl.cpp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        "QByteArray asn1ObjectId(ASN1_OBJECT *object)",
        "QByteArray asn1ObjectId(const ASN1_OBJECT *object)",
    ),
    (
        "QByteArray asn1ObjectName(ASN1_OBJECT *object)",
        "QByteArray asn1ObjectName(const ASN1_OBJECT *object)",
    ),
    (
        "QMultiMap<QByteArray, QString> mapFromX509Name(X509_NAME *name)",
        "QMultiMap<QByteArray, QString> mapFromX509Name(const X509_NAME *name)",
    ),
    (
        "        X509_NAME_ENTRY *e = q_X509_NAME_get_entry(name, i);",
        "        const X509_NAME_ENTRY *e = q_X509_NAME_get_entry(name, i);",
    ),
    (
        "QVariant x509UnknownExtensionToValue(X509_EXTENSION *ext)",
        "QVariant x509UnknownExtensionToValue(const X509_EXTENSION *ext)",
    ),
    (
        "        ASN1_OCTET_STRING *value = q_X509_EXTENSION_get_data(ext);",
        "        const ASN1_OCTET_STRING *value = q_X509_EXTENSION_get_data(ext);",
    ),
    (
        "QVariant x509ExtensionToValue(X509_EXTENSION *ext)",
        "QVariant x509ExtensionToValue(const X509_EXTENSION *ext)",
    ),
    (
        "    ASN1_OBJECT *obj = q_X509_EXTENSION_get_object(ext);",
        "    const ASN1_OBJECT *obj = q_X509_EXTENSION_get_object(ext);",
    ),
    (
        "        X509_EXTENSION *ext = q_X509_get_ext(x509, i);",
        "        const X509_EXTENSION *ext = q_X509_get_ext(x509, i);",
    ),
    (
        "X509CertificateBase::X509CertificateExtension X509CertificateOpenSSL::convertExtension(X509_EXTENSION *ext)",
        "X509CertificateBase::X509CertificateExtension X509CertificateOpenSSL::convertExtension(const X509_EXTENSION *ext)",
    ),
]

for old_text, new_text in replacements:
    if old_text not in text:
        sys.exit(f"unable to patch QtBase X509 const-correctness: {old_text}")
    text = text.replace(old_text, new_text)

old = '''\
            // keyid
            if (auth_key->keyid) {
                QByteArray keyid(reinterpret_cast<const char *>(auth_key->keyid->data),
                                 auth_key->keyid->length);
                result["keyid"_L1] = keyid.toHex();
            }
'''
new = '''\
            // keyid
            if (auth_key->keyid) {
                QByteArray keyid(reinterpret_cast<const char *>(q_ASN1_STRING_get0_data(auth_key->keyid)),
                                 q_ASN1_STRING_length(auth_key->keyid));
                result["keyid"_L1] = keyid.toHex();
            }
'''
if old not in text:
    sys.exit("unable to patch QtBase authority key identifier handling")
text = text.replace(old, new, 1)

old = '''\
            QHostAddress ipAddress;
            switch (len) {
            case 4: // IPv4
                ipAddress = QHostAddress(qFromBigEndian(*reinterpret_cast<quint32 *>(genName->d.iPAddress->data)));
                break;
            case 16: // IPv6
                ipAddress = QHostAddress(reinterpret_cast<quint8 *>(genName->d.iPAddress->data));
                break;
            default: // Unknown IP address format
                break;
            }
'''
new = '''\
            QHostAddress ipAddress;
            const unsigned char *addressData = q_ASN1_STRING_get0_data(genName->d.iPAddress);
            switch (len) {
            case 4: // IPv4
                ipAddress = QHostAddress(qFromBigEndian(*reinterpret_cast<const quint32 *>(addressData)));
                break;
            case 16: // IPv6
                ipAddress = QHostAddress(reinterpret_cast<const quint8 *>(addressData));
                break;
            default: // Unknown IP address format
                break;
            }
'''
if old not in text:
    sys.exit("unable to patch QtBase IP subject alternative name handling")
text = text.replace(old, new, 1)

old = '''\
    if (ASN1_INTEGER *serialNumber = q_X509_get_serialNumber(x509)) {
        QByteArray hexString;
        hexString.reserve(serialNumber->length * 3);
        for (int a = 0; a < serialNumber->length; ++a) {
            hexString += QByteArray::number(serialNumber->data[a], 16).rightJustified(2, '0');
            hexString += ':';
        }
        hexString.chop(1);
        backend->serialNumberString = hexString;
    }
'''
new = '''\
    if (ASN1_INTEGER *serialNumber = q_X509_get_serialNumber(x509)) {
        const unsigned char *serialData = q_ASN1_STRING_get0_data(serialNumber);
        const int serialLength = q_ASN1_STRING_length(serialNumber);
        QByteArray hexString;
        hexString.reserve(serialLength * 3);
        for (int a = 0; a < serialLength; ++a) {
            hexString += QByteArray::number(serialData[a], 16).rightJustified(2, '0');
            hexString += ':';
        }
        hexString.chop(1);
        backend->serialNumberString = hexString;
    }
'''
if old not in text:
    sys.exit("unable to patch QtBase certificate serial number handling")
text = text.replace(old, new, 1)

path.write_text(text)
PY

  python3 - "$srcdir/src/plugins/tls/openssl/qsslsocket_openssl_symbols_p.h" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    ("int q_ASN1_STRING_length(ASN1_STRING *a);", "int q_ASN1_STRING_length(const ASN1_STRING *a);"),
    ("int q_ASN1_STRING_to_UTF8(unsigned char **a, ASN1_STRING *b);", "int q_ASN1_STRING_to_UTF8(unsigned char **a, const ASN1_STRING *b);"),
    ("int q_i2t_ASN1_OBJECT(char *buf, int buf_len, ASN1_OBJECT *obj);", "int q_i2t_ASN1_OBJECT(char *buf, int buf_len, const ASN1_OBJECT *obj);"),
    ("int q_OBJ_obj2txt(char *buf, int buf_len, ASN1_OBJECT *obj, int no_name);", "int q_OBJ_obj2txt(char *buf, int buf_len, const ASN1_OBJECT *obj, int no_name);"),
    ("ASN1_OBJECT *q_X509_EXTENSION_get_object(X509_EXTENSION *a);", "const ASN1_OBJECT *q_X509_EXTENSION_get_object(const X509_EXTENSION *a);"),
    ("X509_EXTENSION *q_X509_get_ext(X509 *a, int b);", "const X509_EXTENSION *q_X509_get_ext(X509 *a, int b);"),
    ("const X509V3_EXT_METHOD *q_X509V3_EXT_get(X509_EXTENSION *a);", "const X509V3_EXT_METHOD *q_X509V3_EXT_get(const X509_EXTENSION *a);"),
    ("void *q_X509V3_EXT_d2i(X509_EXTENSION *a);", "void *q_X509V3_EXT_d2i(const X509_EXTENSION *a);"),
    ("int q_X509_EXTENSION_get_critical(X509_EXTENSION *a);", "int q_X509_EXTENSION_get_critical(const X509_EXTENSION *a);"),
    ("ASN1_OCTET_STRING *q_X509_EXTENSION_get_data(X509_EXTENSION *a);", "const ASN1_OCTET_STRING *q_X509_EXTENSION_get_data(const X509_EXTENSION *a);"),
    ("X509_NAME *q_X509_get_issuer_name(X509 *a);", "const X509_NAME *q_X509_get_issuer_name(X509 *a);"),
    ("X509_NAME *q_X509_get_subject_name(X509 *a);", "const X509_NAME *q_X509_get_subject_name(X509 *a);"),
    ("int q_X509_NAME_entry_count(X509_NAME *a);", "int q_X509_NAME_entry_count(const X509_NAME *a);"),
    ("X509_NAME_ENTRY *q_X509_NAME_get_entry(X509_NAME *a,int b);", "const X509_NAME_ENTRY *q_X509_NAME_get_entry(const X509_NAME *a,int b);"),
    ("ASN1_STRING *q_X509_NAME_ENTRY_get_data(X509_NAME_ENTRY *a);", "const ASN1_STRING *q_X509_NAME_ENTRY_get_data(const X509_NAME_ENTRY *a);"),
    ("ASN1_OBJECT *q_X509_NAME_ENTRY_get_object(X509_NAME_ENTRY *a);", "const ASN1_OBJECT *q_X509_NAME_ENTRY_get_object(const X509_NAME_ENTRY *a);"),
]

for old_text, new_text in replacements:
    if old_text not in text:
        sys.exit(f"unable to patch QtBase OpenSSL symbol declaration: {old_text}")
    text = text.replace(old_text, new_text)

path.write_text(text)
PY

  python3 - "$srcdir/src/plugins/tls/openssl/qx509_openssl_p.h" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_text = "    static X509CertificateExtension convertExtension(X509_EXTENSION *ext);"
new_text = "    static X509CertificateExtension convertExtension(const X509_EXTENSION *ext);"
if old_text not in text:
    sys.exit("unable to patch QtBase X509 extension declaration")
text = text.replace(old_text, new_text)

path.write_text(text)
PY

  python3 - "$srcdir/src/plugins/tls/openssl/qsslsocket_openssl_symbols.cpp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    ("DEFINEFUNC(int, ASN1_STRING_length, ASN1_STRING *a, a, return 0, return)", "DEFINEFUNC(int, ASN1_STRING_length, const ASN1_STRING *a, a, return 0, return)"),
    ("DEFINEFUNC2(int, ASN1_STRING_to_UTF8, unsigned char **a, a, ASN1_STRING *b, b, return 0, return)", "DEFINEFUNC2(int, ASN1_STRING_to_UTF8, unsigned char **a, a, const ASN1_STRING *b, b, return 0, return)"),
    ("DEFINEFUNC3(int, i2t_ASN1_OBJECT, char *a, a, int b, b, ASN1_OBJECT *c, c, return -1, return)", "DEFINEFUNC3(int, i2t_ASN1_OBJECT, char *a, a, int b, b, const ASN1_OBJECT *c, c, return -1, return)"),
    ("DEFINEFUNC4(int, OBJ_obj2txt, char *a, a, int b, b, ASN1_OBJECT *c, c, int d, d, return -1, return)", "DEFINEFUNC4(int, OBJ_obj2txt, char *a, a, int b, b, const ASN1_OBJECT *c, c, int d, d, return -1, return)"),
    ("DEFINEFUNC(ASN1_OBJECT *, X509_EXTENSION_get_object, X509_EXTENSION *a, a, return nullptr, return)", "DEFINEFUNC(const ASN1_OBJECT *, X509_EXTENSION_get_object, const X509_EXTENSION *a, a, return nullptr, return)"),
    ("DEFINEFUNC2(X509_EXTENSION *, X509_get_ext, X509 *a, a, int b, b, return nullptr, return)", "DEFINEFUNC2(const X509_EXTENSION *, X509_get_ext, X509 *a, a, int b, b, return nullptr, return)"),
    ("DEFINEFUNC(const X509V3_EXT_METHOD *, X509V3_EXT_get, X509_EXTENSION *a, a, return nullptr, return)", "DEFINEFUNC(const X509V3_EXT_METHOD *, X509V3_EXT_get, const X509_EXTENSION *a, a, return nullptr, return)"),
    ("DEFINEFUNC(void *, X509V3_EXT_d2i, X509_EXTENSION *a, a, return nullptr, return)", "DEFINEFUNC(void *, X509V3_EXT_d2i, const X509_EXTENSION *a, a, return nullptr, return)"),
    ("DEFINEFUNC(int, X509_EXTENSION_get_critical, X509_EXTENSION *a, a, return 0, return)", "DEFINEFUNC(int, X509_EXTENSION_get_critical, const X509_EXTENSION *a, a, return 0, return)"),
    ("DEFINEFUNC(ASN1_OCTET_STRING *, X509_EXTENSION_get_data, X509_EXTENSION *a, a, return nullptr, return)", "DEFINEFUNC(const ASN1_OCTET_STRING *, X509_EXTENSION_get_data, const X509_EXTENSION *a, a, return nullptr, return)"),
    ("DEFINEFUNC(X509_NAME *, X509_get_issuer_name, X509 *a, a, return nullptr, return)", "DEFINEFUNC(const X509_NAME *, X509_get_issuer_name, X509 *a, a, return nullptr, return)"),
    ("DEFINEFUNC(X509_NAME *, X509_get_subject_name, X509 *a, a, return nullptr, return)", "DEFINEFUNC(const X509_NAME *, X509_get_subject_name, X509 *a, a, return nullptr, return)"),
    ("DEFINEFUNC(int, X509_NAME_entry_count, X509_NAME *a, a, return 0, return)", "DEFINEFUNC(int, X509_NAME_entry_count, const X509_NAME *a, a, return 0, return)"),
    ("DEFINEFUNC2(X509_NAME_ENTRY *, X509_NAME_get_entry, X509_NAME *a, a, int b, b, return nullptr, return)", "DEFINEFUNC2(const X509_NAME_ENTRY *, X509_NAME_get_entry, const X509_NAME *a, a, int b, b, return nullptr, return)"),
    ("DEFINEFUNC(ASN1_STRING *, X509_NAME_ENTRY_get_data, X509_NAME_ENTRY *a, a, return nullptr, return)", "DEFINEFUNC(const ASN1_STRING *, X509_NAME_ENTRY_get_data, const X509_NAME_ENTRY *a, a, return nullptr, return)"),
    ("DEFINEFUNC(ASN1_OBJECT *, X509_NAME_ENTRY_get_object, X509_NAME_ENTRY *a, a, return nullptr, return)", "DEFINEFUNC(const ASN1_OBJECT *, X509_NAME_ENTRY_get_object, const X509_NAME_ENTRY *a, a, return nullptr, return)"),
]

for old_text, new_text in replacements:
    if old_text not in text:
        sys.exit(f"unable to patch QtBase OpenSSL symbol definition: {old_text}")
    text = text.replace(old_text, new_text)

path.write_text(text)
PY
}

build_libtorrent() {
  msg "=== libtorrent-rasterbar ${LT_VER} ==="
  local a="$DL/libtorrent-rasterbar-${LT_VER}.tar.gz"
  fetch "$LT_URL" "$a" "$LT_SHA256"
  rm_rf_safe "$SRC/libtorrent-rasterbar-${LT_VER}"
  extract "$a" "$SRC"
  apply_libtorrent_openssl4_patch "$SRC/libtorrent-rasterbar-${LT_VER}"

  local b="$BUILD/libtorrent-${LT_VER}"
  rm_rf_safe "$b"
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
  write_build_stamp "$STAMP_DIR" libtorrent "$LT_VER"
}

fetch_qtbase() {
  msg "=== QtBase source ${QT_VER} ==="
  local a="$DL/qtbase-everywhere-src-${QT_VER}.tar.xz"
  fetch "$QTBASE_URL" "$a" "$QTBASE_SHA256"
  rm_rf_safe "$SRC/qtbase-everywhere-src-${QT_VER}"
  extract "$a" "$SRC"
  apply_qtbase_openssl4_patch "$SRC/qtbase-everywhere-src-${QT_VER}"
}

fetch_qttools() {
  msg "=== QtTools source ${QT_VER} ==="
  local a="$DL/qttools-everywhere-src-${QT_VER}.tar.xz"
  fetch "$QTTOOLS_URL" "$a" "$QTTOOLS_SHA256"
  rm_rf_safe "$SRC/qttools-everywhere-src-${QT_VER}"
  extract "$a" "$SRC"
}

build_qtbase_host() {
  msg "=== QtBase (host) ${QT_VER} ==="
  local srcdir="$SRC/qtbase-everywhere-src-${QT_VER}"
  local b="$BUILD/qtbase-host-${QT_VER}"
  rm_rf_safe "$b"

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
  write_build_stamp "$HOST_QT_STAMP_DIR" qtbase-host "$QT_VER"
}

build_qtbase_target() {
  msg "=== QtBase (target static) ${QT_VER} ==="
  local srcdir="$SRC/qtbase-everywhere-src-${QT_VER}"
  local b="$BUILD/qtbase-target-${QT_VER}"
  rm_rf_safe "$b"

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
  write_build_stamp "$STAMP_DIR" qtbase-target "$QT_VER"
}

build_qttools_host() {
  msg "=== QtTools (host, for Linguist tools) ${QT_VER} ==="
  local srcdir="$SRC/qttools-everywhere-src-${QT_VER}"
  local b="$BUILD/qttools-host-${QT_VER}"
  rm_rf_safe "$b"

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
  write_build_stamp "$HOST_QT_STAMP_DIR" qttools-host "$QT_VER"
}

build_qttools_target() {
  msg "=== QtTools (target) ${QT_VER} ==="
  local srcdir="$SRC/qttools-everywhere-src-${QT_VER}"
  local b="$BUILD/qttools-target-${QT_VER}"
  rm_rf_safe "$b"

  cmake_cfg "$srcdir" "$b" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DSTAGING_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_HOST_PATH="$HOST_QT_PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF
  cmake_build_install "$b"
  write_build_stamp "$STAMP_DIR" qttools-target "$QT_VER"
}

build_qbittorrent() {
  msg "=== qBittorrent ${QBT_VER} (${QBT_TAG}, nox) ==="
  local a="$DL/qbittorrent-${QBT_VER}.tar.xz"
  local srcdir="$SRC/qbittorrent-${QBT_VER}"
  local bin="$PREFIX/bin/qbittorrent-nox"
  fetch "$QBT_URL" "$a" "$QBT_SHA256"
  rm_rf_safe "$srcdir"
  extract "$a" "$SRC"
  [[ -d "$srcdir" ]] || die "expected qBittorrent source directory not found: $srcdir"

  local b="$BUILD/qbittorrent-${QBT_VER}"
  rm_rf_safe "$b"
  rm -f -- "$bin"
  cmake_cfg "$srcdir" "$b" \
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

ensure_dep() {
  local dep="$1" build_fn="$2" label
  label="$(dep_label "$dep")"
  if dep_needs_build "$dep"; then
    "$build_fn"
  else
    msg "Skipping ${label}; requested version is already available"
  fi
}

ensure_qtbase() {
  if dep_needs_build qtbase-host || dep_needs_build qtbase-target; then
    fetch_qtbase
  fi
  ensure_dep qtbase-host build_qtbase_host
  ensure_dep qtbase-target build_qtbase_target
}

ensure_qttools() {
  if dep_needs_build qttools-host || dep_needs_build qttools-target; then
    fetch_qttools
  fi
  ensure_dep qttools-host build_qttools_host
  ensure_dep qttools-target build_qttools_target
}

ensure_prerequisites() {
  ensure_dep zlib build_zlib
  ensure_dep openssl build_openssl
  ensure_dep boost build_boost
  ensure_dep libtorrent build_libtorrent
  ensure_qtbase
  ensure_qttools
}

build_qbittorrent_only_guard() {
  if deps_all_current; then
    return 0
  fi

  show_dependency_report
  die "--qbittorrent-only requested, but one or more prerequisites are missing or not current"
}

msg "Build prefix: $PREFIX"
msg "Downloads cache: $DL"
msg "Host Qt prefix: $HOST_QT_PREFIX"

show_dependency_report
choose_default_build_mode
confirm_build_plan
prepare_clean_rebuild_if_needed

if [[ "$DO_QBT_ONLY" == "1" ]]; then
  build_qbittorrent_only_guard
else
  plan_dependency_rebuilds
  show_cascade_rebuild_report
  ensure_prerequisites
fi

build_qbittorrent
verify_static
if [[ "$DO_DEPLOY" == "1" ]]; then
  deploy_artifact
fi
offer_deploy_after_build

msg "All done."
