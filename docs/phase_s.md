# Phase 6: Extreme Performance and Robustness Architecture

## Overview
Phase 6 pushes QwD into the ultra-high-performance tier (≈1M reads/sec) by overhauling the I/O system, enabling 2-bit sequence encoding, implementing SIMD newline detection, and optimizing the parallel scheduler. It introduces an optional Fast Mode with approximate algorithms for extreme throughput.

## Block I/O Architecture
Replaces line-by-line reading with chunked 1–4MB block reading.

```text
I/O Buffer Flow
[ Disk ] → [ 4MB Buffer ] → [ SIMD Newline Scanner ] → [ Slices ] → [ Pipeline ]
```

## SIMD Newline Detection
Uses vector operations to quickly find `
` characters in large chunks of memory, bypassing slow byte-by-byte scalar scanning.

## 2-Bit Sequence Encoding
ASCII sequences are converted immediately into a 2-bit representation (A=00, C=01, G=10, T=11). This reduces memory footprint by 4× and enables extremely fast rolling bit-hashes for k-mer and GC calculations.

## Entropy Lookup Tables
Replaces expensive floating-point `log2()` calls with a precomputed static lookup table for `p * log2(p)`, drastically accelerating the Sequence Entropy stage.

## Fast Mode Approximations
With the `--fast` flag, exact hashing in the Duplication and Overrepresented Sequence stages is replaced by:
- Prefix hashing (analyzing only the first 50bp).
- Bloom filters or early cutoff (stopping after 100k reads).
This trades absolute precision for massive cache locality and throughput improvements.

## Parallel Scheduler Optimizations
```text
Parallel Worker Architecture
[ Main Thread (I/O) ] → [ Batch of 256 Reads ] → [ Worker Thread (Local Stages) ]
```
Introduces read batching and thread-local metrics to eliminate lock contention. Metrics are deterministically merged in the finalize phase.
