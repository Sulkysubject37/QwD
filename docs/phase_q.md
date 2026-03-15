# Phase Q: Columnar Genomics Analytics Engine

## Overview
Phase Q transforms QwD's execution model from row-oriented (read-by-read) to columnar processing. By reorganizing genomic data into columnar blocks, we maximize SIMD utilization and cache locality, pushing throughput towards the 2–5M reads/sec range.

## Columnar FASTQ Architecture
Instead of processing one read at a time, the engine groups reads into blocks (e.g., 256–512 reads) and transposes them so that bases at the same relative position across all reads are stored contiguously.

### Transposition Layout
```text
Row-Oriented (Old):          Columnar (New):
Read 1: A C G T ...          Pos 0: [A, T, G, ...] (Reads 1, 2, 3...)
Read 2: T T G C ...    ==>   Pos 1: [C, T, A, ...]
Read 3: G G A A ...          Pos 2: [G, G, A, ...]
```

## Bitplane DNA Representation
For ultra-high-speed analytics, columns are optionally represented as bitplanes (Plane A, C, G, T). Each plane is a bitset where a bit is set if the base at that position matches the plane's base type.
- **GC Content**: `popcount(G_plane | C_plane)`
- **Complexity**: `O(N/64)` using 64-bit word operations.

## Read Graph Sampling (Fast Mode)
In `--fast` mode, the engine builds a lightweight similarity graph using MinHash sketches. This graph is used for:
- Detecting massive contamination.
- Identifying global duplication patterns without exhaustive hashing.
- Sampling overrepresented sequences.

## Hybrid Multicore Scheduling
The `ParallelScheduler` is upgraded to dispatch `FastqColumnBlock` objects. Worker threads perform vectorized operations across the columns of the block, significantly reducing the number of instructions per base.

## Performance Objectives
- **Target Throughput**: 2M – 5M reads/sec.
- **Memory Bound**: O(BlockSize), strictly independent of file size.
- **Precision**: Bit-identical results in Exact Mode.
