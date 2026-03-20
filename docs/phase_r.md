# Phase R: Multicore Throughput Architecture

## Overview
Phase R enables true multicore streaming execution by integrating the `ParallelScheduler` into the pipeline and introducing a batched processing architecture. It decouples the parser from the workers, introduces a lock-free ring buffer for passing data, and uses SIMD for base decoding.

## Multicore Pipeline Architecture
The execution is decoupled: a single parser thread reads the block, detects FASTQ records, and builds batches. These batches are pushed into a lock-free ring buffer and pulled by multiple worker threads.

```text
Parser Thread         Ring Buffer               Worker Pool
[ Parser ]   →   [ ReadBatch Queue ]   →   [ Worker 1 (Local Stages) ]
                                      ↘   [ Worker 2 (Local Stages) ]
                                      ↘   [ Worker N (Local Stages) ]
```

## Batch Processing Model
Reads are processed in batches (default: 512 reads) rather than one by one. This drastically reduces scheduler overhead, improves CPU cache locality, and enables SIMD-friendly loops inside analytical stages.

## Lock-Free Ring Buffer Design
Data is passed from the single parser producer to multiple worker consumers via a bounded, lock-free ring buffer. This minimizes contention and keeps the data flowing efficiently without mutex overhead.

## Zero-Copy & Probabilistic Extension (The 1.1M Objective)
To breach the 1.1 million reads/sec milestone, Phase R has been extended with zero-copy data flow and probabilistic structures.

### 1. Memory-Mapped I/O (`mmap`)
Replaces standard `read()` syscalls with `mmap()`. The engine treats the entire file as a virtual memory array, eliminating the overhead of internal kernel-to-user space copying and the logic of the manual `BlockReader`.

### 2. Zero-Copy Batching
The `BatchBuilder` now stores slices (`[]const u8`) that point directly into the memory-mapped file region. No string duplication occurs between the parser and the worker threads.

### 3. Probabilistic Analytics
In `--fast` mode, heavy stages are replaced with constant-time bitwise operations:
- **Duplication Detection:** Replaced with a **Bloom Filter** (bit-array). This eliminates `StringHashMap` allocations and collision handling.
- **Overrepresented Sequences:** Replaced with an early-cutoff logic combined with a fixed-size sketch.

```text
Ultimate Throughput Flow
[ mmap File ] → [ Slices (Zero-Copy) ] → [ Workers ] → [ Bloom/LUT Stages ]
```
Throughput Target: **300k - 1M reads/sec** (Hardware Dependent).
- Goal: Maintain >1.1M reads/sec on multi-node clusters with sustained memory capping.
