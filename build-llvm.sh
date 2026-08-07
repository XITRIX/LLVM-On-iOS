#!/usr/bin/env bash

set -euo pipefail

LLVM_REVISION="ca7933e47d3a3451d81e72ac174dcb5aa28b59d1"
LLVM_REVISION_SHORT="${LLVM_REVISION:0:16}"
IOS_DEPLOYMENT_TARGET="26.0"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/.build}"
SOURCE_ROOT="${BUILD_ROOT}/llvm-project-${LLVM_REVISION}"
NATIVE_BUILD_ROOT="${BUILD_ROOT}/native-tools"
IOS_BUILD_ROOT="${BUILD_ROOT}/iphoneos-arm64"
INSTALL_ROOT="${BUILD_ROOT}/install/LLVM-iOS26-arm64"
PACKAGE_ROOT="${BUILD_ROOT}/packages"

download_llvm_source() {
    if [[ -f "${SOURCE_ROOT}/.rpcs3-source-revision" ]] &&
       [[ "$(<"${SOURCE_ROOT}/.rpcs3-source-revision")" == "${LLVM_REVISION}" ]]; then
        return
    fi

    rm -rf "${SOURCE_ROOT}"
    mkdir -p "${BUILD_ROOT}"

    local archive="${BUILD_ROOT}/llvm-project-${LLVM_REVISION}.tar.gz"
    curl --fail --location --retry 5 \
        --output "${archive}" \
        "https://github.com/llvm/llvm-project/archive/${LLVM_REVISION}.tar.gz"

    local extracted="${BUILD_ROOT}/llvm-project-${LLVM_REVISION}"
    tar -xzf "${archive}" -C "${BUILD_ROOT}"
    [[ -d "${extracted}" ]]
    printf '%s\n' "${LLVM_REVISION}" > "${SOURCE_ROOT}/.rpcs3-source-revision"
}

build_native_tablegen() {
    download_llvm_source

    cmake -S "${SOURCE_ROOT}/llvm" -B "${NATIVE_BUILD_ROOT}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD=AArch64 \
        -DLLVM_ENABLE_PROJECTS= \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_ENABLE_BINDINGS=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_ZSTD=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DLLVM_ENABLE_CURL=OFF \
        -DLLVM_ENABLE_HTTPLIB=OFF

    cmake --build "${NATIVE_BUILD_ROOT}" --target llvm-tblgen llvm-min-tblgen
    test -x "${NATIVE_BUILD_ROOT}/bin/llvm-tblgen"
    test -x "${NATIVE_BUILD_ROOT}/bin/llvm-min-tblgen"
}

build_ios_llvm() {
    build_native_tablegen

    local sdk_root
    sdk_root="$(xcrun --sdk iphoneos --show-sdk-path)"

    rm -rf "${IOS_BUILD_ROOT}" "${INSTALL_ROOT}"

    cmake -S "${SOURCE_ROOT}/llvm" -B "${IOS_BUILD_ROOT}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${sdk_root}" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET}" \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLVM_TARGET_ARCH=AArch64 \
        -DLLVM_TARGETS_TO_BUILD=AArch64 \
        -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios26.0 \
        -DLLVM_TABLEGEN="${NATIVE_BUILD_ROOT}/bin/llvm-tblgen" \
        -DLLVM_NATIVE_TOOL_DIR="${NATIVE_BUILD_ROOT}/bin" \
        -DLLVM_ENABLE_PROJECTS= \
        -DLLVM_BUILD_LLVM_DYLIB=OFF \
        -DLLVM_LINK_LLVM_DYLIB=OFF \
        -DLLVM_BUILD_TOOLS=OFF \
        -DLLVM_BUILD_UTILS=OFF \
        -DLLVM_INCLUDE_TOOLS=OFF \
        -DLLVM_INCLUDE_UTILS=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_ENABLE_BINDINGS=OFF \
        -DLLVM_ENABLE_THREADS=ON \
        -DLLVM_ENABLE_EH=OFF \
        -DLLVM_ENABLE_RTTI=OFF \
        -DLLVM_ENABLE_FFI=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_ZSTD=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DLLVM_ENABLE_CURL=OFF \
        -DLLVM_ENABLE_HTTPLIB=OFF \
        -DLLVM_ENABLE_LIBPFM=OFF \
        -DLLVM_ENABLE_UNWIND_TABLES=OFF \
        -DLLVM_DISABLE_ASSEMBLY_FILES=ON

    # Installing the aggregate target also pulls in cross-built host utilities.
    # Only the component archives, headers, and CMake package are part of the SDK.
    cmake --build "${IOS_BUILD_ROOT}" --target \
        install-llvm-libraries \
        install-llvm-headers \
        install-cmake-exports
}

validate_ios_llvm() {
    local required_libraries=(
        libLLVMAArch64CodeGen.a
        libLLVMCore.a
        libLLVMExecutionEngine.a
        libLLVMMCJIT.a
        libLLVMPasses.a
        libLLVMRuntimeDyld.a
    )

    test -f "${INSTALL_ROOT}/include/llvm/Config/llvm-config.h"
    test -f "${INSTALL_ROOT}/lib/cmake/llvm/LLVMConfig.cmake"
    grep -Eq '^#define LLVM_ENABLE_THREADS 1$' \
        "${INSTALL_ROOT}/include/llvm/Config/llvm-config.h"

    local library
    for library in "${required_libraries[@]}"; do
        local path="${INSTALL_ROOT}/lib/${library}"
        test -f "${path}"
        [[ "$(lipo -archs "${path}")" == "arm64" ]]
    done

    local probe_root="${BUILD_ROOT}/validation"
    rm -rf "${probe_root}"
    mkdir -p "${probe_root}"

    local archive="${INSTALL_ROOT}/lib/libLLVMCore.a"
    local member
    member="$(xcrun ar -t "${archive}" | awk '/\.o$/ { print; exit }')"
    test -n "${member}"
    (
        cd "${probe_root}"
        xcrun ar -x "${archive}" "${member}"
        xcrun vtool -show-build "${member}" | grep -q 'platform IOS'
        xcrun vtool -show-build "${member}" | grep -q 'minos 26.0'
    )
}

package_ios_llvm() {
    validate_ios_llvm
    mkdir -p "${PACKAGE_ROOT}"

    local build_revision="${GITHUB_SHA:-local}"
    local build_revision_short="${build_revision:0:12}"
    local base_name="LLVM-iOS26-arm64-${LLVM_REVISION_SHORT}-${build_revision_short}"
    local archive="${PACKAGE_ROOT}/${base_name}.tar.xz"
    local checksum="${archive}.sha256"
    local manifest="${PACKAGE_ROOT}/${base_name}.json"

    tar -cJf "${archive}" -C "$(dirname "${INSTALL_ROOT}")" "$(basename "${INSTALL_ROOT}")"
    local archive_digest
    archive_digest="$(shasum -a 256 "${archive}" | awk '{print $1}')"
    printf '%s  %s\n' "${archive_digest}" "$(basename "${archive}")" > "${checksum}"
    (cd "${PACKAGE_ROOT}" && shasum -a 256 -c "$(basename "${checksum}")")

    printf '{\n' > "${manifest}"
    printf '  "schema": 1,\n' >> "${manifest}"
    printf '  "llvm_revision": "%s",\n' "${LLVM_REVISION}" >> "${manifest}"
    printf '  "builder_revision": "%s",\n' "${build_revision}" >> "${manifest}"
    printf '  "target": "arm64-apple-ios26.0",\n' >> "${manifest}"
    printf '  "sdk": "%s",\n' "$(xcrun --sdk iphoneos --show-sdk-version)" >> "${manifest}"
    printf '  "xcode": "%s",\n' "$(xcodebuild -version | tr '\n' ' ')" >> "${manifest}"
    printf '  "archive": "%s",\n' "$(basename "${archive}")" >> "${manifest}"
    printf '  "sha256": "%s"\n' "${archive_digest}" >> "${manifest}"
    printf '}\n' >> "${manifest}"

    printf 'PACKAGE_ARCHIVE=%s\n' "${archive}"
    printf 'PACKAGE_CHECKSUM=%s\n' "${checksum}"
    printf 'PACKAGE_MANIFEST=%s\n' "${manifest}"
}

usage() {
    printf 'Usage: %s <source|native-tools|build|validate|package>\n' "$0"
}

case "${1:-}" in
    source) download_llvm_source ;;
    native-tools) build_native_tablegen ;;
    build) build_ios_llvm ;;
    validate) validate_ios_llvm ;;
    package) package_ios_llvm ;;
    *) usage; exit 64 ;;
esac
