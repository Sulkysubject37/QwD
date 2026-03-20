#!/usr/bin/env bash

set -e

echo "Compiling QwD (ReleaseFast)..."
export PATH=$PATH:/usr/local/zig
zig build -Doptimize=ReleaseFast

REPORT="stress_test_report.md"
echo "# QwD Stress Test Report" > "$REPORT"
echo "" >> "$REPORT"
echo "Date: $(date)" >> "$REPORT"
echo "Machine: $(uname -a)" >> "$REPORT"
echo "" >> "$REPORT"
echo "| Dataset | Threads | Memory Cap | Time (s) | Throughput (reads/s) | Peak RSS (MB) | Status |" >> "$REPORT"
echo "|---------|---------|------------|----------|----------------------|---------------|--------|" >> "$REPORT"

run_test() {
    local file=$1
    local threads=$2
    local mem=$3
    local reads=$4

    echo "Testing $file | Threads: $threads | Mem: ${mem}MB"
    
    # Use /usr/bin/time -l on macOS for peak RSS
    START_TIME=$(date +%s)
    OUT=$(/usr/bin/time -l ./zig-out/bin/qwd qc "$file" --threads "$threads" --max-memory "$mem" 2>&1)
    EXIT_CODE=$?
    END_TIME=$(date +%s)
    
    DURATION=$((END_TIME - START_TIME))
    if [ "$DURATION" -eq 0 ]; then DURATION=1; fi
    THROUGHPUT=$((reads / DURATION))
    
    if [ "$EXIT_CODE" -eq 0 ]; then
        STATUS="✅ PASS"
        PEAK_BYTES=$(echo "$OUT" | grep "maximum resident set size" | awk '{print $1}')
        PEAK_MB=$((PEAK_BYTES / 1024 / 1024))
    else
        STATUS="❌ FAIL ($EXIT_CODE)"
        PEAK_MB="N/A"
    fi
    
    echo "| $file | $threads | ${mem}MB | ${DURATION}s | ${THROUGHPUT} | ${PEAK_MB} | $STATUS |" >> "$REPORT"
}

# 1M Tests
run_test "test_1M.fastq" 1 256 1000000
run_test "test_1M.fastq" 4 256 1000000
run_test "test_1M.fastq" 8 256 1000000
run_test "test_1M.fastq" 4 128 1000000
run_test "test_1M.fastq" 4 64  1000000

# 10M Tests (if file exists)
if [ -f "stress_10M.fastq" ]; then
    run_test "stress_10M.fastq" 1 512 10000000
    run_test "stress_10M.fastq" 4 512 10000000
    run_test "stress_10M.fastq" 8 512 10000000
    run_test "stress_10M.fastq" 4 256 10000000
fi

echo "Stress tests completed. Report generated in $REPORT"
cat "$REPORT"
