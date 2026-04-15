#!/bin/sh
# Build a static FFmpeg binary.
#
# Usage: build.sh <version> <output-name>
# Example: build.sh 6.1.4 ffmpeg-linux-x64
#
# Assumes build deps are already installed:
#   - Alpine: apk add build-base nasm coreutils curl tar xz git pkgconfig mbedtls-dev mbedtls-static
#     (libx264 is built from source below because Alpine doesn't ship libx264.a)
#   - macOS:  brew install nasm x264 cmake
#     (mbedtls is built from source below because macOS ld prefers Homebrew's
#      .dylib over .a, producing a non-portable binary.)
#
# On Linux, produces a fully static binary (musl, no dynamic linking).
# On macOS, libx264 and FFmpeg libs are statically linked; system libs (libSystem) link dynamically as required by Apple.

set -eu

VERSION="$1"
OUTPUT="$2"

# x264 revision (current HEAD of stable branch, pinned for reproducibility)
X264_REV="b35605ace3ddf7c1a5d67a2eb553f034aef41d55"
# mbedtls release tag (3.6.x is the current LTS)
MBEDTLS_VERSION="3.6.4"

OS="$(uname -s)"
SRC_URL="https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
SRC_DIR="ffmpeg-${VERSION}"
PREFIX="$(pwd)/local"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

SRC_BIN="ffmpeg"
EXTRA_CFLAGS=""
EXTRA_LDFLAGS=""
EXTRA_LIBS=""
BUILD_MBEDTLS=0
case "${OS}" in
  Linux)
    NPROC=$(nproc)
    EXTRA_LDFLAGS="-static"
    BUILD_X264=1
    ;;
  Darwin)
    NPROC=$(sysctl -n hw.ncpu)
    BUILD_X264=0
    BUILD_MBEDTLS=1
    ;;
  MINGW*|MSYS*)
    NPROC=$(nproc)
    EXTRA_LDFLAGS="-static -L/mingw64/lib"
    EXTRA_CFLAGS="-I/mingw64/include"
    # mbedtls on Windows needs Winsock + Crypto API symbols at static link time;
    # without these the configure probe fails with "mbedTLS not found".
    EXTRA_LIBS="-lws2_32 -lbcrypt"
    BUILD_X264=1
    SRC_BIN="ffmpeg.exe"
    # Preserve mingw64's default search paths so system-installed deps are found.
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig"
    export CPATH="/mingw64/include"
    export LIBRARY_PATH="/mingw64/lib"
    ;;
  *)
    echo "Unsupported OS: ${OS}" >&2
    exit 1
    ;;
esac

if [ "${BUILD_MBEDTLS}" = "1" ]; then
  echo "==> Building mbedTLS ${MBEDTLS_VERSION} from source"
  curl -fL -o mbedtls.tar.gz \
    "https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/mbedtls-${MBEDTLS_VERSION}.tar.gz"
  mkdir mbedtls-src && tar xzf mbedtls.tar.gz -C mbedtls-src --strip-components=1
  cd mbedtls-src
  cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_SHARED_MBEDTLS_LIBRARY=Off \
    -DUSE_STATIC_MBEDTLS_LIBRARY=On \
    -DENABLE_TESTING=Off \
    -DENABLE_PROGRAMS=Off
  cmake --build build -j"${NPROC}"
  cmake --install build
  cd ..
fi

if [ "${BUILD_X264}" = "1" ]; then
  echo "==> Building libx264 from source (rev ${X264_REV})"
  git clone https://code.videolan.org/videolan/x264.git
  cd x264
  git checkout "${X264_REV}"
  ./configure --prefix="${PREFIX}" --enable-static --disable-cli --disable-opencl
  make -j"${NPROC}"
  make install
  cd ..
fi

echo "==> Downloading FFmpeg ${VERSION} source"
curl -fL -o ffmpeg.tar.xz "${SRC_URL}"
tar xf ffmpeg.tar.xz

cd "${SRC_DIR}"

echo "==> Configuring"
./configure \
  --enable-gpl \
  --enable-version3 \
  --enable-libx264 \
  --enable-mbedtls \
  --enable-static \
  --disable-shared \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --pkg-config-flags="--static" \
  ${EXTRA_CFLAGS:+--extra-cflags="${EXTRA_CFLAGS}"} \
  ${EXTRA_LDFLAGS:+--extra-ldflags="${EXTRA_LDFLAGS}"} \
  ${EXTRA_LIBS:+--extra-libs="${EXTRA_LIBS}"}

echo "==> Building (-j${NPROC})"
make -j"${NPROC}"

echo "==> Verifying"
"./${SRC_BIN}" -version | head -n 1
"./${SRC_BIN}" -version | grep -q "ffmpeg version ${VERSION}" \
  || { echo "ERROR: version mismatch" >&2; exit 1; }
"./${SRC_BIN}" -buildconf | grep -q -- "--enable-libx264" \
  || { echo "ERROR: libx264 not enabled" >&2; exit 1; }
"./${SRC_BIN}" -buildconf | grep -q -- "--enable-mbedtls" \
  || { echo "ERROR: mbedtls not enabled" >&2; exit 1; }
"./${SRC_BIN}" -protocols 2>/dev/null | grep -qw "https" \
  || { echo "ERROR: https protocol not available" >&2; exit 1; }

case "${OS}" in
  Linux)
    echo "==> Verifying static linking (no dynamic deps)"
    # `ldd` on a fully static binary on Alpine prints "Not a valid dynamic program"
    # or fails — either way, presence of "=>" lines indicates dynamic linking.
    if ldd "./${SRC_BIN}" 2>&1 | grep -q "=>"; then
      echo "ERROR: ffmpeg has dynamic dependencies:" >&2
      ldd "./${SRC_BIN}" >&2
      exit 1
    fi
    ;;
  Darwin)
    echo "==> Verifying no non-system dylib deps (Homebrew etc.)"
    # Anything outside /usr/lib or /System (e.g. /opt/homebrew, /usr/local)
    # means the binary won't run on a clean Mac.
    NON_SYSTEM_DEPS=$(otool -L "./${SRC_BIN}" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/)' || true)
    if [ -n "${NON_SYSTEM_DEPS}" ]; then
      echo "ERROR: ffmpeg has non-system dynamic deps:" >&2
      echo "${NON_SYSTEM_DEPS}" >&2
      exit 1
    fi
    ;;
esac

echo "==> Stripping"
strip "./${SRC_BIN}"

mv "./${SRC_BIN}" "../${OUTPUT}"
cd ..
echo "==> Done: ${OUTPUT} ($(du -h "${OUTPUT}" | cut -f1))"
