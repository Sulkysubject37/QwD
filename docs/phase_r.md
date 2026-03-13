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

## SIMD Base Decoding
A new `core/simd/base_decode.zig` module is introduced to vectorize ASCII → 2-bit conversion, replacing the scalar `encodeSequence`.

## Deterministic Aggregation
Each worker thread runs the *entire pipeline* on a given batch, keeping its own thread-local metrics. During the `finalize` phase, these local structures (integer counters, array merges, histograms) are deterministically merged to the global aggregator. There are no floating-point reductions that might introduce non-determinism, ensuring outputs match single-threaded execution exactly.
