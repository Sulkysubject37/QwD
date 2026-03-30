#!/usr/bin/env bash
# generate_test_fastq.sh — wrapper for the native Zig FASTQ generator
# Usage: bash generate_test_fastq.sh [OUTPUT] [READS] [SEED]

OUTPUT="${1:-test_1M.fastq}"
READS="${2:-1000000}"
SEED="${3:-42}"

export PATH=$PATH:/usr/local/zig

echo "Building native Zig generator..."
zig build-exe tools/gen_fastq.zig -O ReleaseFast --name gen_fastq 2>&1
echo "Generating $READS reads → $OUTPUT"
./gen_fastq "$OUTPUT" "$READS" "$SEED"
