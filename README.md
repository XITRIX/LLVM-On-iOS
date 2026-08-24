# LLVM on iOS

This fork produces the static LLVM distribution used by the standalone RPCS3 iOS port.

The build is pinned to llvm-project commit
`ca7933e47d3a3451d81e72ac174dcb5aa28b59d1`, matching the LLVM revision used by
RPCS3 commit `3d587726a23f514be0e7c3ac43e2db0cf2fe931a`.

The pinned source is built with
[`patches/aarch64-ghc-emergency-spill.patch`](patches/aarch64-ghc-emergency-spill.patch),
which reserves an AArch64 register-scavenging spill slot for GHC-convention
functions that acquire a stack frame. This prevents a register-pressure failure
seen in RPCS3 PPU recompilation. The failure and original fix were identified by
[ARMSX3](https://github.com/ARMSX2/ARMSX3/commit/b5a715adcf6f81d210fa5fa4d45bc64857ee0f94);
this repository carries a focused implementation against the exact pinned LLVM
revision.

## Distribution

Every successful `master` build publishes both a GitHub Actions artifact and an
immutable GitHub release. The release contains:

- static arm64 libraries targeting iOS 15;
- LLVM headers;
- LLVM CMake package files;
- a SHA-256 checksum; and
- a JSON build manifest containing the source revision, applied patch digest,
  target, SDK, and Xcode version.

The RPCS3 iOS build downloads one exact release asset and verifies its checksum.
Prebuilt LLVM binaries are not committed to either repository.

## Configuration

The workflow first builds a native `llvm-tblgen`, then cross-compiles LLVM for
`arm64-apple-ios15.0`. It enables LLVM threading and the AArch64 target while
disabling Clang, libffi, tests, installed tools, RTTI, exceptions, zlib, and zstd.
Component archives are preserved so RPCS3 can select Core, ExecutionEngine,
MCJIT, Passes, and their transitive dependencies through `LLVMConfig.cmake`.

Set `IOS_DEPLOYMENT_TARGET` to build for a higher deployment target. The builder
rejects targets below iOS 15.0 so its output remains compatible with the minimum
supported Xcode 27 deployment floor.

## Local build

Xcode 26, CMake, and Ninja are required:

```sh
./build-llvm.sh native-tools
./build-llvm.sh build
./build-llvm.sh package
```

Generated source, build, and package files live under `.build/` and are ignored.

The sample application from the upstream project remains for historical reference;
it is not part of the RPCS3 LLVM distribution.
