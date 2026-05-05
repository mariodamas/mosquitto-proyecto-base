#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-build}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
CC_BIN="${CC:-clang}"
CXX_BIN="${CXX:-clang++}"
JOBS="${JOBS:-$(nproc)}"

cmake_configure() {
  local build_dir="$1"

  cmake -S . -B "${build_dir}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_C_COMPILER="${CC_BIN}" \
    -DCMAKE_CXX_COMPILER="${CXX_BIN}" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DDOCUMENTATION=OFF \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE" \
    -DCMAKE_EXE_LINKER_FLAGS="-pie -Wl,-z,relro,-z,now"
}

cmake_build() {
  local build_dir="$1"
  cmake --build "${build_dir}" --clean-first -j"${JOBS}"
}

case "${ACTION}" in
  build)
    cmake_configure build
    cmake_build build
    ;;
  codeql-configure)
    rm -rf build-codeql
    cmake_configure build-codeql
    ;;
  codeql-build)
    cmake_build build-codeql
    ;;
  coverity-configure)
    rm -rf build-coverity
    cmake_configure build-coverity
    ;;
  coverity-build)
    cmake_build build-coverity
    ;;
  *)
    echo "Usage: $0 {build|codeql-configure|codeql-build|coverity-configure|coverity-build}" >&2
    exit 2
    ;;
esac
