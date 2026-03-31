#!/bin/bash
QWD="./zig-out/bin/qwd"
OUT_CSV="validation_results.csv"

# Ensure clean start
rm -f res_*.json validation_results.csv
echo "mode,format,engine,threads,time_sec,reads_sec" > $OUT_CSV

run_test() {
    local mode=$1
    local input=$2
    local engine=$3
    local threads=$4
    local fmt_name=$5
    
    echo "Running: Mode=$mode | Fmt=$fmt_name | Engine=$engine | Threads=$threads"
    
    start=$(date +%s.%N)
    $QWD qc "$input" --mode "$mode" --gzip-mode "$engine" --threads "$threads" --json --quiet > "res_${mode}_${fmt_name}_${engine}_${threads}t.json"
    status=$?
    end=$(date +%s.%N)
    
    if [ $status -ne 0 ]; then
        echo "FAILED: $mode $fmt_name $engine $threads"
        return
    fi
    
    runtime=$(echo "$end - $start" | bc)
    # 1M reads / runtime
    rps=$(echo "1000000 / $runtime" | bc)
    
    echo "$mode,$fmt_name,$engine,$threads,$runtime,$rps" >> $OUT_CSV
}

for t in 1 2 4 8; do
    for mode in "exact" "approx"; do
        # Plain
        run_test "$mode" "benchmark_1M.fastq" "auto" "$t" "plain"
        
        # Standard GZ (qwd and libdeflate)
        run_test "$mode" "benchmark_1M.fastq.gz" "qwd" "$t" "gz"
        run_test "$mode" "benchmark_1M.fastq.gz" "libdeflate" "$t" "gz"
        
        # BGZF (qwd, libdeflate, and auto)
        run_test "$mode" "benchmark_1M.bgzf.gz" "qwd" "$t" "bgzf"
        run_test "$mode" "benchmark_1M.bgzf.gz" "libdeflate" "$t" "bgzf"
        run_test "$mode" "benchmark_1M.bgzf.gz" "auto" "$t" "bgzf"
    done
done

echo "Validation Matrix Complete. Results in $OUT_CSV"
