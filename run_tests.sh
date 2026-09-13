#!/bin/bash
# 测试脚本：本机只有 CommandLineTools（无 Xcode/XCTest），
# Swift Testing 框架和 lib_TestingInterop.dylib 需要手动指定搜索路径。
set -euo pipefail
cd "$(dirname "$0")"

MODULE_CACHE="$PWD/.build/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLT=/Library/Developer/CommandLineTools
FW="$CLT/Library/Developer/Frameworks"
LIB="$CLT/Library/Developer/usr/lib"

env \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  swift test --disable-sandbox \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
