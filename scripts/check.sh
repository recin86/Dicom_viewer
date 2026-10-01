#!/usr/bin/env bash
# Foundation + PIXEL-1 ownership + DISPLAY-1 and native SC color checks.
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
python3 - "$REPORT" "$CACHE/bootstrap-$MODE.json" <<'PY'
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
Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes())
print("PASS: Swift reads the frozen Rust bootstrap revision 1.")
PY

python3 "$ROOT/scripts/prepare-pixel-fixtures.py" "$CACHE/pixel-fixtures"
python3 "$ROOT/scripts/prepare-color-fixtures.py" "$CACHE/color-fixtures-v2"
BIN_DIR="$(swift build --package-path "$ROOT/macos" --scratch-path "$CACHE/swift-$MODE" -c "$MODE" --show-bin-path)"
"$BIN_DIR/ViewerContractChecks" "$CACHE/pixel-fixtures" "$CACHE/pixel-contract-$MODE.json"
"$BIN_DIR/ViewerDisplayChecks" "$CACHE/pixel-fixtures" "$CACHE/native-display-$MODE.json"
"$BIN_DIR/ViewerColorChecks" "$CACHE/color-fixtures-v2" "$CACHE/native-color-$MODE.json"
python3 - "$CACHE/pixel-contract-$MODE.json" "$CACHE/native-display-$MODE.json" "$CACHE/native-color-$MODE.json" "$CACHE/pixel-fixtures" "$CACHE/color-fixtures-v2" <<'PY'
import hashlib
import json
import sys
from pathlib import Path
for report_path in sys.argv[1:4]:
    report = json.loads(Path(report_path).read_text())
    if report.get("passed") is not True:
        raise SystemExit("Pixel ownership, native display or SC color checks failed")
for fixture_directory in sys.argv[4:6]:
    fixtures = Path(fixture_directory)
    manifest = json.loads((fixtures / "manifest.json").read_text())
    for fixture in manifest["fixtures"]:
        if hashlib.sha256((fixtures / fixture["id"]).read_bytes()).hexdigest() != fixture["sha256"]:
            raise SystemExit("A synthetic source fixture changed during checks")
print("PASS: actual native DICOM → Rust handle → separately budgeted Swift copy.")
print("PASS: Metal display matches the bounded Rust reference.")
print("PASS: native SC planar RGB and YBR match independent color literals.")
print("PASS: synthetic source hashes are unchanged.")
PY
if [[ "$UI_CHECK" == true ]]; then
  "$BIN" --ui-smoke-test > "$REPORT"
  python3 - "$REPORT" "$CACHE/shell-ui-$MODE.json" <<'PY'
import json
import sys
from pathlib import Path

info = json.loads(Path(sys.argv[1]).read_text())
if info.get("passed") is not True:
    raise SystemExit(f"Native window/menu/close check failed: {info!r}")
Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes())
print("PASS: native window, menus, enabled opening and final-window termination.")
PY
  "$BIN" --display-smoke-test "$CACHE/pixel-fixtures/display-aspect.dcm" > "$REPORT"
  python3 - "$REPORT" "$CACHE/display-ui-$MODE.json" <<'PY'
import json
import sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
info = json.loads(data)
if info.get("passed") is not True:
    raise SystemExit("Native file opening and drawable presentation check failed")
Path(sys.argv[2]).write_bytes(data)
print("PASS: actual native file opening and Metal drawable presentation.")
PY
fi
