#!/bin/bash
# Capture extended gameplay logs by running full race/session

set -e

PICODRIVE_CMD="${PICODRIVE_CMD:-picodrive}"
DURATION="${DURATION:-180}"  # Default: 3 minutes of gameplay
OUTPUT_DIR="${OUTPUT_DIR:-logs}"

mkdir -p "$OUTPUT_DIR"

echo "[*] Extended Gameplay Log Capture"
echo "[*] Will capture $DURATION seconds of continuous emulation"
echo ""
echo "[*] Instructions:"
echo "    1. When Picodrive starts, the game will begin"
echo "    2. Let it run for the full $DURATION seconds (you can watch or minimize)"
echo "    3. The script will automatically stop capture and analyze"
echo ""
read -p "Ready to start? Press ENTER to begin (Ctrl+C to cancel)"

ROM="${1:-build/vrd_phase4_linked.32x}"
if [ ! -f "$ROM" ]; then
    echo "[!] ROM not found: $ROM"
    exit 1
fi

PHASE=$(basename "$ROM" .32x | grep -o "phase[0-9_]*" | head -1)
OUTPUT_LOG="$OUTPUT_DIR/${PHASE}_extended_$(date +%s).log"

echo "[*] Starting: $PICODRIVE_CMD $ROM"
echo "[*] Capturing to: $OUTPUT_LOG"
echo "[*] Duration: $DURATION seconds"
echo ""

# Start emulator and capture output
timeout $DURATION "$PICODRIVE_CMD" "$ROM" 2>&1 | tee "$OUTPUT_LOG" &
PID=$!

# Show progress
for i in $(seq 1 $DURATION); do
    sleep 1
    # Show DREQ count periodically
    if [ $((i % 30)) -eq 0 ]; then
        count=$(grep -c "DREQ FIFO" "$OUTPUT_LOG" 2>/dev/null || echo "0")
        echo "[*] $i/$DURATION seconds - $count DREQ blocks captured so far"
    fi
done

# Wait for process to finish
wait $PID 2>/dev/null || true

echo ""
echo "[+] Capture complete: $OUTPUT_LOG"

# Count results
total_dreq=$(grep -c "DREQ FIFO" "$OUTPUT_LOG" 2>/dev/null || echo "0")
echo "[*] Total DREQ blocks captured: $total_dreq"

if [ "$total_dreq" -gt 100 ]; then
    echo "[+] Good sample! Analyzing FIFO pattern..."
    echo ""

    # Show first and last timestamp
    first_ts=$(grep "DREQ FIFO" "$OUTPUT_LOG" 2>/dev/null | head -1 | cut -d: -f1-2 || echo "unknown")
    last_ts=$(grep "DREQ FIFO" "$OUTPUT_LOG" 2>/dev/null | tail -1 | cut -d: -f1-2 || echo "unknown")

    echo "First DREQ: $first_ts"
    echo "Last DREQ:  $last_ts"
    echo ""

    # Show clustering
    echo "[*] DREQ clustering pattern:"
    grep "DREQ FIFO" "$OUTPUT_LOG" | cut -d: -f1 | uniq -c | head -20
    echo ""

    echo "[*] To analyze this log with the FIFO analyzer:"
    echo "    python3 tools/analyze_fifo.py '$OUTPUT_LOG'"
else
    echo "[!] Warning: Only $total_dreq DREQ blocks captured (expected >100 for good sample)"
    echo "[!] This might be due to:"
    echo "    - Game stuck in menu/pause"
    echo "    - Emulator performance too slow"
    echo "    - FIFO blocking minimal during this session"
fi
