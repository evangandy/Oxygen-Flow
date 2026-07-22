#!/bin/bash
# Build the whisper.cpp static libraries (with Metal, embedded shaders) that FlowLocal links.
# Run once after cloning, or when you update vendor/whisper.cpp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# A plain `git clone` (without --recurse-submodules) leaves this as an empty directory.
if [ ! -f "vendor/whisper.cpp/CMakeLists.txt" ]; then
  echo "==> vendor/whisper.cpp is empty, fetching submodule…"
  git submodule update --init --recursive
fi

cd "$ROOT/vendor/whisper.cpp"

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_ACCELERATE=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF

cmake --build build -j --config Release
echo "==> whisper static libs:"
find build -name "*.a" | sort

# Refresh the copied public headers used by the CWhisper interop module.
cp include/whisper.h "$ROOT/Sources/CWhisper/include/"
cp ggml/include/*.h "$ROOT/Sources/CWhisper/include/"
echo "==> headers synced to Sources/CWhisper/include"
