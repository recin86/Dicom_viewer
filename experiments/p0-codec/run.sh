#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXP="$ROOT/experiments/p0-codec"
CACHE="${P0_CODEC_CACHE:-$HOME/Library/Caches/dicom-viewer/p0-codec}"
PROFILE="${1:-all}"
case "$PROFILE" in
  all) PROFILES=(baseline charls openjp2 openjpeg combined combined-c) ;;
  baseline|charls|openjp2|openjpeg|combined|combined-c) PROFILES=("$PROFILE") ;;
  *) echo 'usage: run.sh [all|baseline|charls|openjp2|openjpeg|combined|combined-c]' >&2; exit 2 ;;
esac
mkdir -p "$CACHE" "$EXP/results"
command -v uv >/dev/null || { echo 'uv is required for the isolated Python reference environment' >&2; exit 1; }
if [[ ! -x "$CACHE/venv/bin/python" ]]; then
  uv python install 3.12.13
  uv venv --python 3.12.13 "$CACHE/venv"
fi
uv pip sync --python "$CACHE/venv/bin/python" "$EXP/requirements.txt"
export PATH="$CACHE/venv/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=27.0
rustup toolchain install 1.98.1 --profile minimal --component rustfmt --component clippy
# Each feature set has a separate target directory: a previous profile cannot leak codecs.
for profile in "${PROFILES[@]}"; do
  case "$profile" in
    baseline|combined|combined-c) features="$profile" ;;
    charls|openjp2) features="baseline,$profile" ;;
    openjpeg) features="baseline,openjpeg-sys" ;;
  esac
  export CARGO_TARGET_DIR="$CACHE/target-$profile"
  printf 'P0-CODEC build/compare: %s\n' "$profile"
  cargo +1.98.1 build --manifest-path "$EXP/rust/Cargo.toml" --locked --release --no-default-features --features "$features" >"$CACHE/build-$profile.log" 2>&1
  cp "$CARGO_TARGET_DIR/release/p0-codec" "$CACHE/p0-codec-$profile"
  "$CACHE/venv/bin/python" "$EXP/record_build.py" --profile "$profile" --features "$features" \
    --binary "$CACHE/p0-codec-$profile" --report "$EXP/results/build-$profile.json"
  # P0 discoveries are recorded as failures, and must not stop the other feature experiments.
  # The report remains authoritative; nonzero exit is never labelled a passing run.
  if "$CACHE/venv/bin/python" "$EXP/reference/run.py" \
    --binary "$CACHE/p0-codec-$profile" --work-dir "$CACHE/work-$profile" \
    --report "$EXP/results/$profile.json" --profile "$profile" --local-data "$ROOT/local-data"; then
    printf 'P0-CODEC comparison exit: %s pass\n' "$profile"
  else
    printf 'P0-CODEC comparison exit: %s fail (see report)\n' "$profile"
    FAILED=1
  fi
done
exit "${FAILED:-0}"
