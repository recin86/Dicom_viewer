# Shared development environment; source this file from build/check scripts.
# Generated DICOM, codec tools and build products remain outside the repository.
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=27.0

# P0 prepared CMake in its isolated local codec environment. Reuse that tool
# when CMake is absent from PATH; do not install or modify a global runtime.
if ! command -v cmake >/dev/null 2>&1; then
  CODEC_TOOLS="$HOME/Library/Caches/dicom-viewer/p0-codec/venv/bin"
  if [[ -x "$CODEC_TOOLS/cmake" ]]; then
    export PATH="$CODEC_TOOLS:$PATH"
  else
    echo "CMake is required to build the pinned JPEG-LS/JPEG 2000 dependencies." >&2
    exit 1
  fi
fi
