#!/bin/bash
# P0-FFI: build Rust (UniFFI) -> generate Swift bindings -> build Swift (SwiftPM, no Xcode) -> run checks.
# Run from anywhere:  bash experiments/p0-ffi/run.sh        (full checks)
#                     bash experiments/p0-ffi/run.sh mem    (memory follow-up)
#                     bash experiments/p0-ffi/run.sh real   (realistic frame sizes)
# Report: experiments/p0-ffi/results/p0-ffi-report.txt
# Build outputs go OUTSIDE OneDrive (~/Library/Caches/dicom-viewer/...) unless CARGO_TARGET_DIR is set.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
CACHE="$HOME/Library/Caches/dicom-viewer/p0-ffi"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$CACHE/cargo-target}"
SWIFT_SCRATCH="$CACHE/swift-build"
GEN="$CACHE/gen"
mkdir -p "$HERE/results" "$GEN" "$HERE/swift/lib" "$HERE/swift/Sources/p0ffiFFI/include"
REPORT="$HERE/results/p0-ffi-report.txt"
BUILDLOG="$HERE/results/p0-ffi-build.log"
: > "$BUILDLOG"

step() { echo "== $*" | tee -a "$BUILDLOG"; }
fail() { echo "FAILED: $* (see $BUILDLOG)" | tee -a "$BUILDLOG"; exit 1; }

{
  echo "P0-FFI build $(date '+%Y-%m-%d %H:%M:%S %Z')"
  rustc --version; cargo --version; swift --version 2>&1 | head -1
  echo "CARGO_TARGET_DIR=$CARGO_TARGET_DIR"
  echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
} >> "$BUILDLOG" 2>&1

step "1/5 Rust unit tests + release build (first run downloads crates, a few minutes)"
( cd "$HERE/rust" && cargo test --release >> "$BUILDLOG" 2>&1 && cargo build --release --lib >> "$BUILDLOG" 2>&1 ) || fail "cargo build"

REL="$CARGO_TARGET_DIR/release"
[ -f "$REL/libp0ffi.a" ] && [ -f "$REL/libp0ffi.dylib" ] || fail "missing libp0ffi.a / libp0ffi.dylib in $REL"

step "2/5 Generate Swift bindings (uniffi-bindgen 0.32.2, library mode)"
( cd "$HERE/rust" && cargo run -q --release --features bindgen --bin uniffi-bindgen -- \
    generate "$REL/libp0ffi.dylib" --language swift --out-dir "$GEN" >> "$BUILDLOG" 2>&1 ) || fail "uniffi-bindgen"

cp "$GEN/p0ffi.swift" "$HERE/swift/Sources/P0Bench/p0ffi.swift"
cp "$GEN/p0ffiFFI.h" "$HERE/swift/Sources/p0ffiFFI/include/p0ffiFFI.h"
cp "$GEN/p0ffiFFI.modulemap" "$HERE/swift/Sources/p0ffiFFI/include/module.modulemap"
cp "$REL/libp0ffi.a" "$HERE/swift/lib/libp0ffi.a"   # static lib only, so the linker cannot pick the dylib
{
  echo "-- generated signatures"
  grep -n -E "public func (makeFrame|checksumOwned|checksumBorrowed|asyncSleepMs|longTask)|public var bytes" "$HERE/swift/Sources/P0Bench/p0ffi.swift"
  echo "-- Data lift path"
  grep -n -A4 "fileprivate struct FfiConverterData" "$HERE/swift/Sources/P0Bench/p0ffi.swift"
  ls -l "$REL/libp0ffi.a"
} >> "$BUILDLOG" 2>&1

step "3/5 Swift build (SwiftPM, release, Command Line Tools only)"
swift build -c release --package-path "$HERE/swift" --scratch-path "$SWIFT_SCRATCH" >> "$BUILDLOG" 2>&1 || fail "swift build"
BIN="$SWIFT_SCRATCH/release/P0Bench"
[ -x "$BIN" ] || fail "missing $BIN"
ls -l "$BIN" >> "$BUILDLOG"
otool -L "$BIN" >> "$BUILDLOG" 2>&1   # should NOT list libp0ffi.dylib (static link)

if [ "${1:-}" = "real" ]; then
  REALREPORT="$HERE/results/p0-ffi-real.txt"
  step "4/5 Realistic-size repeated transfers (each variant in a separate process)"
  { echo "P0-FFI realistic sizes $(date '+%Y-%m-%d %H:%M:%S %Z')"; echo "units: MiB (phys_footprint); overExpected = afterLoop - base - frames kept alive by the ring"; } > "$REALREPORT"
  RC=0
  for v in real-ct real-dx cache-dx into-ct into-dx into-dx-reuse into-cache-dx into-64m; do
    "$BIN" mem "$v" >> "$REALREPORT" 2>&1 || RC=1
  done
  echo "exit code: $RC" >> "$BUILDLOG"
  step "5/5 Done"
  echo "완료: $REALREPORT (exit $RC)"
  exit $RC
fi

if [ "${1:-}" = "mem" ]; then
  MEMREPORT="$HERE/results/p0-ffi-mem.txt"
  step "4/5 Memory follow-up (each variant in a separate process, 64 MiB frames)"
  { echo "P0-FFI memory follow-up $(date '+%Y-%m-%d %H:%M:%S %Z')"; echo "units: MiB (phys_footprint); peakFrames/retainedFrames are in units of one 64 MiB frame; rust* = Rust global allocator counters"; } > "$MEMREPORT"
  RC=0
  for v in single single-bytes rust-only record record-pool bytes bytes-pool swift-emulate swift-array swift-data; do
    "$BIN" mem "$v" >> "$MEMREPORT" 2>&1 || RC=1
  done
  echo "exit code: $RC" >> "$BUILDLOG"
  step "5/5 Done"
  echo "완료: $MEMREPORT (exit $RC)"
  exit $RC
fi

step "4/5 Run checks"
/usr/bin/time -l "$BIN" > "$REPORT" 2> "$HERE/results/p0-ffi-time.txt"
RC=$?
{ echo; echo "== /usr/bin/time -l (exit $RC)"; grep -E "real|maximum resident|peak memory footprint" "$HERE/results/p0-ffi-time.txt"; } >> "$REPORT"
echo "exit code: $RC" >> "$BUILDLOG"

step "5/5 Done"
echo "완료: $REPORT (exit $RC)"
