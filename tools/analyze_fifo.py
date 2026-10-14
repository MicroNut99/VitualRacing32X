#!/usr/bin/env python3
"""Parse Picodrive logs and analyze FIFO blocking patterns"""

import re
import sys
from collections import defaultdict

def parse_picodrive_log(filename):
    """Extract FIFO blocking events from Picodrive log"""

    fifo_blocks = []
    timestamps = []

    with open(filename, 'r') as f:
        for line in f:
            # Match: HH:MM: message (format from Picodrive output)
            match = re.match(r'(\d+):(\d+): (.+)', line)
            if not match:
                continue

            time_high, time_low = map(int, match.groups()[:2])
            message = match.group(3)

            # Construct timestamp from the time values
            timestamp = time_high + time_low / 1000.0

            if 'DREQ FIFO w16 without 68S' in message:
                fifo_blocks.append(timestamp)
                timestamps.append(timestamp)

    return fifo_blocks, timestamps

def analyze_fifo_blocks(fifo_blocks, timestamps):
    """Calculate FIFO blocking statistics"""

    if not fifo_blocks:
        print("No FIFO blocks detected")
        return

    total_blocks = len(fifo_blocks)
    time_window = timestamps[-1] - timestamps[0]
    blocks_per_second = total_blocks / time_window if time_window > 0 else 0

    # Assuming 60 FPS, calculate blocks per frame
    frames = time_window * 60
    blocks_per_frame = total_blocks / frames if frames > 0 else 0

    # Find clusters (consecutive blocks)
    clusters = []
    current_cluster = [fifo_blocks[0]]

    for i in range(1, len(fifo_blocks)):
        if fifo_blocks[i] - fifo_blocks[i-1] < 0.001:  # Within 1ms
            current_cluster.append(fifo_blocks[i])
        else:
            clusters.append(current_cluster)
            current_cluster = [fifo_blocks[i]]
    clusters.append(current_cluster)

    print("=== FIFO BLOCKING ANALYSIS ===\n")
    print(f"Total blocks: {total_blocks}")
    print(f"Time window: {time_window:.2f}s")
    print(f"Blocks/second: {blocks_per_second:.1f}")
    print(f"Blocks/frame (60 FPS): {blocks_per_frame:.1f}")
    print(f"\nClusters: {len(clusters)}")
    print(f"Avg blocks/cluster: {total_blocks / len(clusters):.1f}")
    print(f"Max cluster size: {max(len(c) for c in clusters)}")

    # Distribution by time window (1-second buckets)
    print(f"\n=== BLOCKING DISTRIBUTION (by second) ===")
    bucket_size = 1.0
    bucket_count = int(time_window / bucket_size) + 1
    buckets = [0] * bucket_count

    for timestamp in timestamps:
        bucket_idx = int((timestamp - timestamps[0]) / bucket_size)
        if 0 <= bucket_idx < bucket_count:
            buckets[bucket_idx] += 1

    # Show buckets with activity
    active_buckets = [(i, count) for i, count in enumerate(buckets) if count > 0]
    if active_buckets:
        print(f"Blocks concentrated in {len(active_buckets)} of {bucket_count} time windows")
        if len(active_buckets) <= 20:
            for bucket_idx, count in active_buckets:
                start_time = timestamps[0] + bucket_idx * bucket_size
                print(f"  {start_time:7.1f}s: {count:3d} blocks")
        else:
            print("First 10 active windows:")
            for bucket_idx, count in active_buckets[:10]:
                start_time = timestamps[0] + bucket_idx * bucket_size
                print(f"  {start_time:7.1f}s: {count:3d} blocks")
            print("Last 10 active windows:")
            for bucket_idx, count in active_buckets[-10:]:
                start_time = timestamps[0] + bucket_idx * bucket_size
                print(f"  {start_time:7.1f}s: {count:3d} blocks")

    # Estimate impact
    stall_cycles_per_block = 10  # Conservative estimate
    cycles_per_frame = 23000000 / 60 / 23000000  # Frame time in MHz cycles
    total_stall = blocks_per_frame * stall_cycles_per_block
    impact_percent = (total_stall / cycles_per_frame) * 100

    print(f"\n=== ESTIMATED IMPACT ===" )
    print(f"Stall time per frame: ~{total_stall:.0f} cycles")
    print(f"Percentage of frame: {impact_percent:.1f}%")
    print(f"Potential FPS gain if fixed: +{(impact_percent/100)*60:.1f}%")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_fifo.py picodrive_output.log")
        sys.exit(1)

    blocks, times = parse_picodrive_log(sys.argv[1])
    analyze_fifo_blocks(blocks, times)

if __name__ == '__main__':
    main()
