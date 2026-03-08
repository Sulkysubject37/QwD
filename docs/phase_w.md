# Phase W: Advanced Streaming Analytics

## Overview
Phase W extends QwD with deeper sequencing diagnostics that continue to operate within a single streaming pass with fixed, deterministic memory.

## Advanced Analytics Stages
1. **Length Distribution**: Computes a histogram of read lengths into fixed bins (0-100, 100-500, 500-1000, 1000-5000, 5000-10000, 10000+).
2. **N50 Stage**: Maintains a histogram of all read lengths and computes the N50 metric (the length L such that 50% of total bases are contained in reads of length >= L).
3. **Quality Decay**: Tracks the mean PHRED quality score per base position across all reads up to a maximum position (default 10,000).
4. **Sequence Entropy**: Measures Shannon entropy per read to detect low-complexity sequences (e.g., poly-A tails).
5. **Adapter Detection**: Analyzes the most frequent k-mers in the read suffixes (last 20 bases) to detect potential adapter contamination.

## Algorithms
- **Entropy**: Computed as $H = - \sum p_i \log_2(p_i)$ where $p_i$ is the frequency of each base (A, C, G, T).
- **N50**: Calculated during `finalize()` by iterating through the cumulative distribution of read lengths from the histogram.
- **Quality Decay**: Uses fixed-size arrays `quality_sum[MAX_POS]` and `base_count[MAX_POS]` to compute positional means.
- **Adapter Detection**: Uses a 4^k array (where k=8) to count k-mers only in the suffix of each read.

## Architecture Diagram
```text
FASTQ
 ↓
Parser
 ↓
Scheduler
 ↓
Trim → Filter → QC → GC → Length → kmer → entropy → quality_decay → adapter_detect
 ↓
Metrics
```

All these stages run in one streaming pass over the input FASTQ file.
