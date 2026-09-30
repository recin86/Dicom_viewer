#!/usr/bin/env bash
# P0-FFI-CONTRACT: Rust checks -> UniFFI Swift bindings -> SwiftPM build (CLT only) -> contract checks.
# Usage (from anywhere, on the target Mac):  bash experiments/p0-ffi-contract/run.sh
# Committable outputs: results/contract-results.json, results/environment.json (no local paths).
# Build logs and binaries stay in ~/Library/Caches/dicom-viewer/p0-ffi-contract/.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
CACHE="${P0_CONTRACT_CACHE:-$HOME/Library/Caches/dicom-viewer/p0-ffi-contract}"
export CARGO_TARGET_DIR="$CACHE/cargo-target"
SWIFT_SCRATCH="$CACHE/swift-build"
GEN="$CACHE/gen"
LOG="$CACHE/build.log"
TOOLCHAIN=1.98.1
mkdir -p "$CACHE" "$GEN" "$HERE/results" "$HERE/swift/lib" "$HERE/swift/Sources/p0contractFFI/include" "$HERE/swift/Sources/P0ContractCopy/include"
: > "$LOG"
step() { echo "== $*" | tee -a "$LOG"; }
fail() {
  echo "FAILED: $* (log: $LOG)" | tee -a "$LOG"
  # Local-only copy for the coordinating AI: last lines with the home path masked (git-ignored).
  tail -n 120 "$LOG" | sed "s#$HOME#~#g" > "$HERE/results/failure-log.txt"
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "this script must run on the target Mac"
rustup toolchain install "$TOOLCHAIN" --profile minimal --component rustfmt --component clippy >> "$LOG" 2>&1 || fail "rustup toolchain $TOOLCHAIN"
CARGO="cargo +$TOOLCHAIN"

rm -f "$HERE/results/contract-results.json" "$HERE/results/environment.json"  # never leave stale results
step "1/5 Rust fmt, unit tests, clippy, release build"
cd "$HERE/rust" || fail "cd rust"
$CARGO fmt --check >> "$LOG" 2>&1 || fail "cargo fmt --check"
$CARGO test --locked --release >> "$LOG" 2>&1 || fail "cargo test"
$CARGO clippy --locked --release --all-targets -- -D warnings >> "$LOG" 2>&1 || fail "cargo clippy"
$CARGO build --locked --release --lib >> "$LOG" 2>&1 || fail "cargo build"
cd "$HERE" || fail "cd experiment"
REL="$CARGO_TARGET_DIR/release"
[ -f "$REL/libp0contract.a" ] && [ -f "$REL/libp0contract.dylib" ] || fail "missing libp0contract.a/.dylib"

step "2/5 UniFFI 0.32.2 Swift bindings (library mode)"
( cd "$HERE/rust" && $CARGO run -q --locked --release --features bindgen --bin uniffi-bindgen -- \
    generate "$REL/libp0contract.dylib" --language swift --out-dir "$GEN" ) >> "$LOG" 2>&1 || fail "uniffi-bindgen"
cp "$GEN/p0contract.swift" "$HERE/swift/Sources/P0ContractCheck/p0contract.swift"
cp "$GEN/p0contractFFI.h" "$HERE/swift/Sources/p0contractFFI/include/p0contractFFI.h"
cp "$GEN/p0contractFFI.modulemap" "$HERE/swift/Sources/p0contractFFI/include/module.modulemap"
cp "$HERE/include/p0_contract_copy.h" "$HERE/swift/Sources/P0ContractCopy/include/p0_contract_copy.h"
cp "$REL/libp0contract.a" "$HERE/swift/lib/libp0contract.a"   # static only: the linker cannot pick the dylib

step "3/5 Swift build (SwiftPM release, Command Line Tools)"
swift build -c release --package-path "$HERE/swift" --scratch-path "$SWIFT_SCRATCH" >> "$LOG" 2>&1 || fail "swift build"
BIN="$SWIFT_SCRATCH/release/P0ContractCheck"
[ -x "$BIN" ] || fail "missing P0ContractCheck binary"
if otool -L "$BIN" | grep -q libp0contract; then fail "binary links libp0contract dynamically"; fi

step "4/5 Environment and hashes"
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
{
  printf '{\n'
  printf '  "task_id": "P0-FFI-CONTRACT",\n'
  printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "base_commit": "%s",\n' "$(git -C "$ROOT" --no-optional-locks rev-parse HEAD 2>/dev/null || echo unavailable)"
  printf '  "macos": "%s",\n  "macos_build": "%s",\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
  printf '  "cpu": "%s",\n' "$(sysctl -n machdep.cpu.brand_string)"
  printf '  "rustc": "%s",\n  "cargo": "%s",\n' "$(rustc +$TOOLCHAIN --version)" "$($CARGO --version)"
  printf '  "swift": "%s",\n' "$(swift --version 2>&1 | head -1 | sed 's/"/\\"/g')"
  printf '  "xcode_select": "%s",\n' "$(xcode-select -p 2>/dev/null | sed "s#^$HOME#~#")"
  printf '  "deployment_target": "%s",\n' "$MACOSX_DEPLOYMENT_TARGET"
  printf '  "uniffi": "0.32.2",\n'
  printf '  "static_link_only": true,\n'
  printf '  "sha256": {\n'
  printf '    "rust/src/lib.rs": "%s",\n' "$(sha "$HERE/rust/src/lib.rs")"
  printf '    "rust/Cargo.lock": "%s",\n' "$(sha "$HERE/rust/Cargo.lock")"
  printf '    "include/p0_contract_copy.h": "%s",\n' "$(sha "$HERE/include/p0_contract_copy.h")"
  printf '    "swift/Sources/P0ContractCheck/main.swift": "%s",\n' "$(sha "$HERE/swift/Sources/P0ContractCheck/main.swift")"
  printf '    "swift/Sources/P0ContractCheck/FrameCopy.swift": "%s",\n' "$(sha "$HERE/swift/Sources/P0ContractCheck/FrameCopy.swift")"
  printf '    "generated/p0contract.swift": "%s",\n' "$(sha "$GEN/p0contract.swift")"
  printf '    "libp0contract.a": "%s",\n' "$(sha "$REL/libp0contract.a")"
  printf '    "P0ContractCheck": "%s"\n' "$(sha "$BIN")"
  printf '  }\n}\n'
} > "$HERE/results/environment.json"

step "5/5 Contract checks"
"$BIN" "$HERE/results/contract-results.json" >> "$LOG" 2>&1
RC=$?
grep -E '^\[(PASS|FAIL|NOT-RUN|INFO)\]|^summary' "$LOG" || true
echo "완료: experiments/p0-ffi-contract/results/contract-results.json (exit $RC)"
exit $RC
