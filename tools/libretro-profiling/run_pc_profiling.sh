#!/bin/bash
# VRD PC-Level Profiling Runner
# Captures program counter-level hotspots for Slave CPU workload analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROM="${1:-roms/Virtua Racing Deluxe (USA).32x}"
FRAMES="${2:-2400}"

# Output files
FRAME_LOG="$SCRIPT_DIR/vrd_profile_pc_frames.csv"
PC_LOG="$SCRIPT_DIR/vrd_profile_pc.csv"

# Convert ROM to absolute path
ROM_ABS="$(cd "$(dirname "$ROM")" && pwd)/$(basename "$ROM")"

# Check if ROM exists
if [ ! -f "$ROM_ABS" ]; then
    echo "ERROR: ROM not found: $ROM"
    echo "Usage: $0 [rom_path] [frames]"
    echo "  rom_path: Path to VRD ROM (default: roms/Virtua Racing Deluxe (USA).32x)"
    echo "  frames:   Number of frames to profile (default: 2400)"
    exit 1
fi

echo "=== VRD PC-Level Profiling ==="
echo "ROM: $ROM_ABS"
echo "Frames: $FRAMES"
echo "Frame log: $FRAME_LOG"
echo "PC log: $PC_LOG"
echo ""

# Run profiling with PC-level instrumentation
cd "$SCRIPT_DIR"
VRD_PROFILE_LOG="$FRAME_LOG" \
VRD_PROFILE_FRAMES="$FRAMES" \
VRD_PROFILE_PC=1 \
VRD_PROFILE_PC_LOG="$PC_LOG" \
./profiling_frontend "$ROM_ABS" $FRAMES --autoplay

echo ""
echo "=== Profiling Complete ==="
echo "Frame data: $FRAME_LOG"
echo "PC data: $PC_LOG"
echo ""
echo "Next steps:"
echo "  1. Analyze frame data: python3 analyze_profile.py $FRAME_LOG"
echo "  2. Analyze PC data: python3 analyze_pc_profile.py $PC_LOG"
