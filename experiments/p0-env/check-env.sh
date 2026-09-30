#!/bin/bash
# P0-ENV: 개발 환경 점검. 읽기 전용이며 설치나 설정 변경을 하지 않는다.
# 실행: bash experiments/p0-env/check-env.sh   (프로젝트 폴더에서)
# 결과: experiments/p0-env/env-report.txt
cd "$(dirname "$0")"
OUT="env-report.txt"
TMP="$(mktemp -d)"
run() { echo; echo "\$ $*"; "$@" 2>&1 || echo "(exit $?)"; }
{
echo "P0-ENV report  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "== OS / hardware"
run sw_vers
run uname -m
run sysctl -n machdep.cpu.brand_string
run sysctl -n hw.memsize
run sysctl -n hw.perflevel0.physicalcpu hw.perflevel1.physicalcpu
echo; echo "\$ system_profiler SPDisplaysDataType (filtered)"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Total Number of Cores|Metal|Resolution|UI Looks like|Retina" || true
echo; echo "== Apple developer tools"
run xcode-select -p
run xcodebuild -version
echo; echo "\$ pkgutil CLT version"
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>&1 | grep -E "version|install-time" || echo "(CLT package info not found)"
run xcrun --show-sdk-version
run xcrun --show-sdk-path
run swift --version
run xcrun -f metal
run xcrun -f metallib
run which codesign
echo; echo "== Rust"
export PATH="$HOME/.cargo/bin:$PATH"
run rustup --version
run rustup show active-toolchain
run rustc --version
run cargo --version
run rustup target list --installed
echo "CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-(unset)}"
echo; echo "== Other tools"
run brew --version
run cmake --version
run python3 --version
run git --version
echo; echo "== Swift + Metal runtime test (compile in temp dir, nothing installed)"
cat > "$TMP/m.swift" <<'SW'
import Metal
import AppKit
guard let d = MTLCreateSystemDefaultDevice() else { print("NO METAL DEVICE"); exit(1) }
print("Metal device:", d.name, "| unified memory:", d.hasUnifiedMemory, "| maxBuffer MiB:", d.maxBufferLength >> 20)
let src = "#include <metal_stdlib>\nusing namespace metal;\nkernel void k(device float* a [[buffer(0)]], uint i [[thread_position_in_grid]]) { a[i] = a[i] * 2.0; }"
do { let lib = try d.makeLibrary(source: src, options: nil); print("runtime shader compile: OK, functions:", lib.functionNames) }
catch { print("runtime shader compile: FAILED", error) }
print("AppKit linked:", NSApplication.self)
SW
echo "\$ swiftc -O m.swift"
if swiftc -O "$TMP/m.swift" -o "$TMP/m" 2>&1; then "$TMP/m" 2>&1; else echo "(swiftc failed)"; fi
} > "$OUT" 2>&1
rm -rf "$TMP"
echo "완료: $(pwd)/$OUT"
