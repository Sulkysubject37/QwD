# Phase Q: Columnar Genomics & Vertical SIMD Engine

## Overview
Phase Q represents the shift from row-oriented processing to a high-density **Columnar Analytics Engine**. By leveraging SIMD-parallel transposition and fused bitplane analytics, QwD now operates on genomics data as a bit-matrix rather than a sequence of strings.

## Key Architectural Pillars

### 1. In-Register SIMD Transposition
To eliminate the memory-write bottleneck, transposition from ASCII rows to columnar blocks is performed entirely in CPU registers using `8x8` and `16x16` shuffle kernels. This reduces memory bus pressure by 32x compared to scalar transposition.

### 2. Fused Bitplane Analytics
Stages like **GC Content**, **Nucleotide Composition**, and **N-Statistics** are fused into a single bitwise pass. 
- The engine converts 1024-read blocks into 4 parallel Bitplanes (A, C, G, T).
- Analytics are reduced to hardware-level `popcount` operations:
  - `GC = popcount(Plane_G | Plane_C)`
  - `Complexity: O(N/64)`

### 3. Columnar K-mer Engine
Leveraging the block layout, the K-mer counting stage has been fully vectorized. It hashes 32 reads simultaneously using a rolling shift-and-mask technique entirely inside vector registers.

### 4. Bounded MinHash Duplicate Detection (Fast Mode)
Fast mode introduces a mathematically sound MinHash Duplicate sketch mechanism that bounds memory footprint to `<32MB` irrespective of dataset size, avoiding the O(N) memory blowup of exact `HashMap` tracking.

### 5. Parallel Transposition & Autonomous Workers
The "Producer Bottleneck" is eliminated by moving transposition and parsing into the worker threads. The main thread's only role is handing out 16MB memory-mapped chunks.

### 4. Vertical SIMD FASTQ Scanner (The 5M Breakthrough)
The parser itself is vectorized. Instead of sequential line reading, the engine uses a 32-lane SIMD scanner to identify record boundaries (`\n@`, `\n+`) across a raw chunk. This allows the engine to skip millions of individual byte-comparisons.

## Data Flow
```text
[ mmap File ] 
      ↓ 
[ 16MB Raw Chunks ] (Distributed to Workers)
      ↓ 
[ Vertical SIMD Scanner ] (Finds 32 records at once)
      ↓ 
[ Register Transpose ] (Rows → Columns in L1)
      ↓ 
[ Fused Bitplane Kernels ] (Popcount Analytics)
      ↓ 
[ Deterministic Merge ] (Aggregated Global Results)
```

## Performance Targets
- **Throughput**: 2M – 5M reads/sec (Compute Bound).
- **Memory**: strictly O(1) resident per thread (~85MB total).
- **Correctness**: Bit-identical to standard row-based execution.
