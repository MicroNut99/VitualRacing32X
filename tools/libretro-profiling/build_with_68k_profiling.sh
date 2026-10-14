#!/bin/bash
#
# Build PicoDrive libretro with 68K + SH2 PC-level profiling
#
# This script:
# 1. Applies the v3 profiling patch (68K + SH2 PC sampling)
# 2. Builds picodrive_libretro.so with profiling enabled
# 3. Copies the binary to tools/libretro-profiling/
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
PICODRIVE_DIR="$PROJECT_ROOT/third_party/picodrive"
PATCH_FILE="$SCRIPT_DIR/libretro_vrd_profiling_v3_pc.patch"

cd "$PICODRIVE_DIR"

echo "=== PicoDrive Profiling Build ==="
echo "PicoDrive dir: $PICODRIVE_DIR"
echo "Patch file: $PATCH_FILE"
echo ""

# Check if patch is already applied
if git diff --quiet; then
    echo "Applying profiling patch..."
    git apply "$PATCH_FILE"
    echo "✓ Patch applied"
else
    echo "⚠ Working tree has uncommitted changes"
    echo "  If patch already applied, continuing with build..."
fi

echo ""
echo "=== Building libretro core ==="
make -f Makefile.libretro platform=unix clean
make -f Makefile.libretro platform=unix -j$(nproc)

echo ""
echo "=== Copying binary ==="
cp picodrive_libretro.so "$SCRIPT_DIR/"
ls -lh "$SCRIPT_DIR/picodrive_libretro.so"

echo ""
echo "=== Build Complete ==="
echo "Binary: $SCRIPT_DIR/picodrive_libretro.so"
echo ""
echo "Usage:"
echo "  VRD_PROFILE_LOG=frame.csv \\"
echo "  VRD_PROFILE_PC=1 \\"
echo "  VRD_PROFILE_PC_LOG=pc.csv \\"
echo "  ./profiling_frontend /path/to/rom.32x 2400 --autoplay"
echo ""
