#!/bin/bash
# Builds libmygojs.so (QuickJS-ng + the mygojs bridge):
#   ./build.sh host      -> native/build/host/libmygojs.so (for headless tests)
#   ./build.sh android   -> android/app/src/main/jniLibs/<abi>/libmygojs.so
# Android is built with the system clang (any host arch) against the NDK's
# sysroot, so no x86_64-only NDK toolchain is needed. NDK_SYSROOT defaults to
# the hybrid r28c NDK under $ANDROID_HOME/ndk (see README).
set -euo pipefail
cd "$(dirname "$0")"
SRC="mygojs.c quickjs-amalgam.c"
CFLAGS="-O2 -fPIC -fvisibility=hidden -D_GNU_SOURCE -w -std=gnu11"
what=${1:-all}

if [[ $what == host || $what == all ]]; then
  mkdir -p build/host
  clang $CFLAGS -shared -o build/host/libmygojs.so $SRC -lm -lpthread
  echo "built build/host/libmygojs.so"
fi

if [[ $what == android || $what == all ]]; then
  NDK=${NDK:-${ANDROID_HOME:-/workspace/work/tools/android-sdk}/ndk/28.2.13676358}
  TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
  SYSROOT=${NDK_SYSROOT:-$TC/sysroot}
  RES=$(ls -d $TC/lib/clang/* | head -1)
  API=24
  for abi in arm64-v8a armeabi-v7a x86_64; do
    case $abi in
      arm64-v8a) triple=aarch64-linux-android; rt=aarch64 ;;
      armeabi-v7a) triple=armv7a-linux-androideabi; rt=arm ;;
      x86_64) triple=x86_64-linux-android; rt=x86_64 ;;
    esac
    out=../android/app/src/main/jniLibs/$abi
    mkdir -p $out
    clang --target=$triple$API --sysroot=$SYSROOT -resource-dir=$RES -fuse-ld=lld \
      -rtlib=compiler-rt --unwindlib=none $CFLAGS -shared \
      -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 -Wl,-soname,libmygojs.so -Wl,--no-undefined \
      -o $out/libmygojs.so $SRC -lm -ldl -llog
    /usr/lib/llvm-19/bin/llvm-strip --strip-unneeded $out/libmygojs.so 2>/dev/null || true
    echo "built $out/libmygojs.so"
  done
fi
