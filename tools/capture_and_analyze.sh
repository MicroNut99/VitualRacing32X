#!/bin/bash
# Script to capture Picodrive logs for FIFO analysis

set -e

PICODRIVE_CMD="${PICODRIVE_CMD:-picodrive}"
OUTPUT_DIR="${OUTPUT_DIR:-logs}"
ANALYSIS_DIR="${ANALYSIS_DIR:-analysis}"

# Create output directories
mkdir -p "$OUTPUT_DIR" "$ANALYSIS_DIR"

echo "[*] FIFO Bottleneck Analysis - Log Capture and Analysis"
echo ""

# Test if Picodrive is available
if ! command -v "$PICODRIVE_CMD" &> /dev/null; then
    echo "[!] Picodrive not found. Please ensure Picodrive is in PATH or set PICODRIVE_CMD"
    echo "[!] Usage: PICODRIVE_CMD=/path/to/picodrive ./tools/capture_and_analyze.sh"
    exit 1
fi

# Phase 3.2 Baseline
echo "[*] Step 1: Capturing Phase 3.2 baseline logs..."
echo "    Run the game for 30 seconds at pit stop, then quit"
echo "    Starting: $PICODRIVE_CMD build/vrd_phase3_final.32x"
echo ""

"$PICODRIVE_CMD" build/vrd_phase3_final.32x 2>&1 | tee "$OUTPUT_DIR/phase3_baseline.log" || true

if [ ! -f "$OUTPUT_DIR/phase3_baseline.log" ] || [ ! -s "$OUTPUT_DIR/phase3_baseline.log" ]; then
    echo "[!] Phase 3.2 log capture failed or empty"
    exit 1
fi

echo "[+] Phase 3.2 log captured: $OUTPUT_DIR/phase3_baseline.log"
echo ""

# Phase 4.1 Optimized
echo "[*] Step 2: Capturing Phase 4.1 optimized logs..."
echo "    Run the game for 30 seconds at pit stop, then quit"
echo "    Starting: $PICODRIVE_CMD build/vrd_phase4_linked.32x"
echo ""

"$PICODRIVE_CMD" build/vrd_phase4_linked.32x 2>&1 | tee "$OUTPUT_DIR/phase4_optimized.log" || true

if [ ! -f "$OUTPUT_DIR/phase4_optimized.log" ] || [ ! -s "$OUTPUT_DIR/phase4_optimized.log" ]; then
    echo "[!] Phase 4.1 log capture failed or empty"
    exit 1
fi

echo "[+] Phase 4.1 log captured: $OUTPUT_DIR/phase4_optimized.log"
echo ""

# Analyze Phase 3.2
echo "[*] Step 3: Analyzing Phase 3.2 FIFO behavior..."
python3 tools/analyze_fifo.py "$OUTPUT_DIR/phase3_baseline.log" > "$ANALYSIS_DIR/phase3_fifo_analysis.txt"
echo "[+] Analysis saved to: $ANALYSIS_DIR/phase3_fifo_analysis.txt"
cat "$ANALYSIS_DIR/phase3_fifo_analysis.txt"
echo ""

# Analyze Phase 4.1
echo "[*] Step 4: Analyzing Phase 4.1 FIFO behavior..."
python3 tools/analyze_fifo.py "$OUTPUT_DIR/phase4_optimized.log" > "$ANALYSIS_DIR/phase4_fifo_analysis.txt"
echo "[+] Analysis saved to: $ANALYSIS_DIR/phase4_fifo_analysis.txt"
cat "$ANALYSIS_DIR/phase4_fifo_analysis.txt"
echo ""

# Comparison
echo "[*] Step 5: Comparison Summary"
echo "=========================================="
echo "Phase 3.2 Baseline vs Phase 4.1 Optimized"
echo "=========================================="
echo ""
echo "--- Phase 3.2 Baseline ---"
head -20 "$ANALYSIS_DIR/phase3_fifo_analysis.txt"
echo ""
echo "--- Phase 4.1 Optimized ---"
head -20 "$ANALYSIS_DIR/phase4_fifo_analysis.txt"
echo ""

echo "[+] Analysis complete!"
