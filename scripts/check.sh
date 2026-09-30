#!/usr/bin/env bash
# Foundation + PIXEL-1 acceptance. Full display/GPU tests are still future work.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI_CHECK=false
MODE=debug
PROFILE=dev
for option in "$@"; do
  case "$option" in
    --ui) UI_CHECK=true ;;
    --release) MODE=release; PROFILE=release ;;
    *) echo "Usage: scripts/check.sh [--release] [--ui]" >&2; exit 2 ;;
  esac
done
source "$ROOT/scripts/environment.sh"
CACHE="${DICOM_VIEWER_CACHE:-$HOME/Library/Caches/dicom-viewer/p1}"
export CARGO_TARGET_DIR="$CACHE/rust"
cd "$ROOT"

cargo fmt --all -- --check
cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
cargo test --locked --workspace --lib --profile "$PROFILE"
bash "$ROOT/scripts/build.sh" "$MODE"
BIN="$CACHE/app-$MODE/DICOM Viewer.app/Contents/MacOS/ViewerApp"
REPORT="$(mktemp "$CACHE/bootstrap.XXXXXX")"
trap 'rm -f "$REPORT"' EXIT
"$BIN" --smoke-test > "$REPORT"
python3 - "$REPORT" <<'PY'
import json
import sys
from pathlib import Path

info = json.loads(Path(sys.argv[1]).read_text())
expected = {
    "api_revision": 1,
    "core_version": "0.1.0",
    "dicom_rs_version": "0.10.0",
    "frame_decode_implemented": False,
}
if info != expected:
    raise SystemExit(f"Rust–Swift bootstrap mismatch: {info!r}")
print("PASS: Swift reads Rust bootstrap revision 1; DICOM opening remains disabled.")
PY

python3 "$ROOT/scripts/prepare-pixel-fixtures.py" "$CACHE/pixel-fixtures"
BIN_DIR="$(swift build --package-path "$ROOT/macos" --scratch-path "$CACHE/swift-$MODE" -c "$MODE" --show-bin-path)"
"$BIN_DIR/ViewerContractChecks" "$CACHE/pixel-fixtures" "$CACHE/pixel-contract-$MODE.json"
python3 - "$CACHE/pixel-contract-$MODE.json" "$CACHE/pixel-fixtures" <<'PY'
import hashlib
import json
import sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text())
if report.get("passed") is not True:
    raise SystemExit("PIXEL-1 contract checks failed")
fixtures = Path(sys.argv[2])
manifest = json.loads((fixtures / "manifest.json").read_text())
for fixture in manifest["fixtures"]:
    if hashlib.sha256((fixtures / fixture["id"]).read_bytes()).hexdigest() != fixture["sha256"]:
        raise SystemExit("A synthetic source fixture changed during checks")
print("PASS: actual native DICOM → Rust handle → separately budgeted Swift copy.")
print("PASS: synthetic source hashes are unchanged.")
PY
if [[ "$UI_CHECK" == true ]]; then
  "$BIN" --ui-smoke-test > "$REPORT"
  python3 - "$REPORT" <<'PY'
import json
import sys
from pathlib import Path

info = json.loads(Path(sys.argv[1]).read_text())
if info.get("passed") is not True:
    raise SystemExit(f"Native window/menu/close check failed: {info!r}")
print("PASS: native window, menus, disabled opening and final-window termination.")
PY
fi
