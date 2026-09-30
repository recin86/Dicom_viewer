#!/usr/bin/env bash
# Product foundation: locked Rust -> pinned UniFFI -> statically linked Swift app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-debug}"
case "$MODE" in
  debug) PROFILE=dev; RUST_DIR=debug ;;
  release) PROFILE=release; RUST_DIR=release ;;
  *) echo "Usage: scripts/build.sh [debug|release]" >&2; exit 2 ;;
esac
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "This development build requires Apple Silicon macOS." >&2
  exit 1
fi
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( OS_MAJOR < 27 )); then
  echo "This product requires macOS 27.0 or later." >&2
  exit 1
fi

source "$ROOT/scripts/environment.sh"
CACHE="${DICOM_VIEWER_CACHE:-$HOME/Library/Caches/dicom-viewer/p1}"
export CARGO_TARGET_DIR="$CACHE/rust"
SWIFT_SCRATCH="$CACHE/swift-$MODE"
mkdir -p "$CACHE"
GEN="$(mktemp -d "$CACHE/bindings.XXXXXX")"
trap 'rm -rf "$GEN"' EXIT
cd "$ROOT"

echo "Building Rust core and boundary ($MODE)…"
cargo build --locked -p viewer-ffi --lib --profile "$PROFILE"
REL="$CARGO_TARGET_DIR/$RUST_DIR"
echo "Generating Swift bindings with UniFFI 0.32.2…"
cargo run --quiet --locked -p viewer-ffi --features bindgen --bin viewer-bindgen \
  --profile "$PROFILE" -- generate "$REL/libviewer_ffi.dylib" --language swift --out-dir "$GEN"

mkdir -p "$ROOT/macos/Sources/ViewerBindings" "$ROOT/macos/Sources/viewer_ffiFFI/include" "$ROOT/macos/lib"
cp "$GEN/viewer_ffi.swift" "$ROOT/macos/Sources/ViewerBindings/viewer_ffi.swift"
cp "$GEN/viewer_ffiFFI.h" "$ROOT/macos/Sources/viewer_ffiFFI/include/viewer_ffiFFI.h"
cp "$GEN/viewer_ffiFFI.modulemap" "$ROOT/macos/Sources/viewer_ffiFFI/include/module.modulemap"
cp "$REL/libviewer_ffi.a" "$ROOT/macos/lib/libviewer_ffi.a"

echo "Building Swift app ($MODE)…"
swift build --package-path "$ROOT/macos" --scratch-path "$SWIFT_SCRATCH" -c "$MODE"
BIN_DIR="$(swift build --package-path "$ROOT/macos" --scratch-path "$SWIFT_SCRATCH" -c "$MODE" --show-bin-path)"
BIN="$BIN_DIR/ViewerApp"
if otool -L "$BIN" | grep -q libviewer_ffi; then
  echo "Unexpected dynamic Rust linkage." >&2
  exit 1
fi
echo "Built: $BIN"

# A local development wrapper for launch/visual inspection, not a P5 release.
# Its provisional identifier does not settle the final product name (OQ-09).
APP="$CACHE/app-$MODE/DICOM Viewer.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/macos/Resources/Info.plist" "$APP/Contents/Info.plist"
# Replace the executable inode: overwriting a previously launched Mach-O can
# leave macOS with a cached code signature for its old pages (SIGKILL at launch).
cp "$BIN" "$APP/Contents/MacOS/.ViewerApp.new"
mv -f "$APP/Contents/MacOS/.ViewerApp.new" "$APP/Contents/MacOS/ViewerApp"
# SwiftPM signs a standalone Mach-O. Seal its new bundle context for local use;
# this is ad-hoc only, with no developer account, notarization or distribution.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Development app: $APP"
