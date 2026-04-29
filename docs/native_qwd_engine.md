# Native QwD Engine: Technical Reference (v1.3.0 Raja Reform)

## Overview
The QwD Engine is a high-density computational core specialized for genomic sequence analytics. It combines a custom DEFLATE decompression engine with a vertical SIMD analytical core, designed for scale-invariant stability and multi-threaded efficiency.

---

## Core Decompression Components

### 1. The Bit-Sieve (`BitSieve`)
At the heart of the engine is a 64-bit sliding bit-buffer.
- **Buffer Mechanism**: Maintains a `u64` bit-stream. Refills are triggered whenever the bit count drops below the maximum possible symbol length (15 bits).
- **In-Register Extraction**: Uses bitwise shifts and masks to extract variable-length bitfields without CPU pipeline stalls.
- **Byte Alignment**: Provides `alignToByte()` for zero-copy transitions between compressed and uncompressed blocks (Type 0).

### 2. High-Speed Huffman Decoder (`HuffmanDecoder`)
The engine utilizes a 12-bit primary lookup table (LUT) for O(1) symbol resolution.
- **Memory Locality**: The 4096-entry `u32` table (16KB) is designed to fit entirely within the CPU's L1 Data Cache.
- **Entry Encoding**: Each LUT entry packs the symbol and its bit-length into a single 32-bit word, allowing for simultaneous consumption and decoding.
- **Canonical Construction**: Implements the RFC 1951 algorithm for building prefix codes from bit-length arrays, ensuring 100% compatibility with standard GZIP/ZLIB streams.

### 3. Circular LZ77 Engine (`Lz77Engine`)
Handles string back-references using a 32KB circular window.
- **Wrapping Logic**: Uses bitwise masking (`& 0x7FFF`) for O(1) position wrapping, avoiding conditional branches.
- **Optimized Copies**: Leverages optimized `memcpy` equivalents for long back-references, significantly accelerating the reconstruction of repetitive genomic sequences.

---

## Hardened Parallel Architecture

### 1. The Double-Pipeline Model
To maximize throughput, QwD v1.3.0 implements a **concurrent double-pipeline** in `ParallelScheduler`:
- **Stage 1 (Decompression)**: A `Feeder` thread reads raw BGZF blocks and dispatches them to a `bgzf_queue`. Worker threads pull from this queue and decompress blocks into ordered slots.
- **Stage 2 (Analysis)**: The main thread acts as an orchestrator, parsing decompressed data from slots into `raw_batch` chunks. These batches are pushed to a `work_queue`.
- **Stage 3 (Execution)**: Worker threads pull `raw_batch` chunks, performing SIMD transposition into bitplanes and executing the analytical pipeline.
- **Result**: Both I/O-heavy decompression and CPU-heavy analysis are fully parallelized, eliminating the sequential bottlenecks of standard genomic tools.

### 2. Hurricane-Spin Protection
Earlier versions utilized `std.Thread.yield()` in tight loops, causing high CPU usage during idle periods. 
- **Block-Wait Backoff**: Replaced with a smart backoff mechanism (nanosecond sleeps). 
- **Efficiency**: Reduces idling CPU overhead to **<5%** while maintaining sub-millisecond responsiveness when new data arrives.

---

## Scale-Invariant Stability

### 1. Static VTable Hard-Binding
To resolve "Bad pointer dereference" errors during multi-threaded execution, all analytical stages now utilize **static VTable constants**.
- **Mechanism**: Stage method tables are defined as `const` at the type level, ensuring the `Stage` interface always points to stable, globally-available memory.

### 2. Heap-Allocated Sequence Persistence
Analytical stages like `DuplicationStage` and `OverrepresentedStage` have transitioned from 1024-byte stack buffers to **heap-allocated sequence buffers**.
- **Long-Read Support**: Capable of processing sequences up to **1MB per read**.
- **Memory Safety**: Prevents stack overflows and memory corruption when encountering non-standard or large-scale genomic data.

---

## Performance Profile (10M Reads Stress Test)
| Metric | EXACT Mode (4 Threads) | 
| :--- | :--- |
| **Total Time** | **~34.0s** |
| **Throughput** | **~294,000 reads/sec** |
| **CPU Efficiency** | **~3.5x Scaling** |
| **Stability** | **100% (Scale-Invariant)** |

*Note: Total system footprint is strictly governed by the `GlobalAllocator`, ensuring stability even under extreme memory contention.*
