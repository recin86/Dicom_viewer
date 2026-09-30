#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Always rebuild before launch so an old executable cannot mask a source error.
bash "$ROOT/scripts/build.sh" debug
CACHE="${DICOM_VIEWER_CACHE:-$HOME/Library/Caches/dicom-viewer/p1}"
exec "$CACHE/app-debug/DICOM Viewer.app/Contents/MacOS/ViewerApp" "$@"
