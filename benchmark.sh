#!/usr/bin/env bash

set -e

echo "Compiling Native Zig Application (ReleaseFast)..."
export PATH=$PATH:/usr/local/zig
zig build -Doptimize=ReleaseFast

echo "Done. Running Benchmarks."
echo "# Native Zig QwD Benchmark Report" > benchmark_report.md
echo "" >> benchmark_report.md
echo "Date: $(date)" >> benchmark_report.md
echo "" >> benchmark_report.md

run_bench() {
    local file=$1
    local threads=$2
    local mem=$3

    echo "Running > $file | Threads: $threads | Max Memory: ${mem}MB"
    echo "### $file — Threads: $threads, Max-Memory: ${mem}MB" >> benchmark_report.md
    echo '```' >> benchmark_report.md

    set +e
    /usr/bin/time -l ./zig-out/bin/qwd qc "$file" --threads "$threads" --max-memory "$mem" 2>> benchmark_report.md
    set -e

    echo '```' >> benchmark_report.md
    echo "" >> benchmark_report.md
    echo "Completed."
}

# ── 1M Dataset ──────────────────────────────────────────────────
echo "## stress_1M.fastq (1 Million Reads)" >> benchmark_report.md

run_bench "stress_1M.fastq"  1  256
run_bench "stress_1M.fastq"  4  256
run_bench "stress_1M.fastq"  8  256
run_bench "stress_1M.fastq"  16 256

# Memory-bounded 1M (reasonable ceilings)
run_bench "stress_1M.fastq"  1  64
run_bench "stress_1M.fastq"  4  128
run_bench "stress_1M.fastq"  8  128

# ── 10M Dataset ──────────────────────────────────────────────────
echo "## stress_10M.fastq (10 Million Reads)" >> benchmark_report.md

run_bench "stress_10M.fastq" 1  256
run_bench "stress_10M.fastq" 4  256
run_bench "stress_10M.fastq" 8  256
run_bench "stress_10M.fastq" 16 256

echo "All tests completed."
