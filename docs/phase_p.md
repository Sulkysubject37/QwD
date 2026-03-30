# Phase P: Universal GZIP Native Engine & Mode Separation

## Overview
Phase P transforms QwD into a compressed-data-native genomics engine. It introduces a high-performance **Async Gzip Engine** with SIMD-accelerated decompression, while refactoring the execution model to separate analytical strategy from decompression strategy. 

By overlapping background decompression with foreground analytical parsing, QwD eliminates the "GZIP tax" and achieves throughput that actually exceeds uncompressed file reading.

## Orthogonal Execution Model
QwD enforces two independent axes of execution to ensure clarity and predictable behavior.

### Axis 1: Analytical Mode (`--mode`)
- **`exact`** (Default): Deterministic, exhaustive processing. Guaranteed bit-identical results across all thread counts and decompression modes.
- **`approx`**: Heuristic-based acceleration (e.g., probabilistic duplication detection via Bloom filters).

### Axis 2: Decompression Mode (`--gzip-mode`)
- **`auto`** (Default): Detects BGZF and uses the optimized SIMD fast-path.
- **`libdeflate`**: Uses `libdeflate` SIMD kernels (AVX2/NEON) for decompression.
- **`qwd`**: Uses the **Pure-Zig Native Engine**. This is a zero-dependency implementation achieving performance parity with `libdeflate`. See **[Native Engine Reference](native_qwd_engine.md)** for details.
- **`compat`**: Standard library streaming fallback for non-blocked GZIP files.

## Architecture: Async Prefetch Engine
Decompression is no longer a blocking operation in the main parser thread.

1. **Background Prefetcher**: A dedicated thread decompresses blocks ahead of the parser and stores them in a high-speed `RingBuffer`.
2. **Bit-Sieve Core (NATIVE_QWD)**: A custom DEFLATE engine featuring a 64-bit sliding bit-buffer and branchless Huffman decoding.
3. **BGZF Specialization**: Natively parses the `BC` (Block Content) extra field to enable independent block processing and multi-core scaling.
4. **Header-Restoring Proxy**: Ensures 100% compatibility with standard GZIP tools by transparently yielding peeked header bytes back to the fallback engine.

## Performance: Defeating the "GZIP Tax"
Integrated BGZF processing is **18% faster** than reading uncompressed FASTQ files due to reduced disk I/O and efficient SIMD scheduling.

| Method | Engine | Throughput (1M Reads) | Status |
| :--- | :--- | :--- | :--- |
| **BGZF (Native Async)** | **`qwd`** | **~207,000 reads/sec** | **Verified Stable** |
| **BGZF (SIMD Async)** | **`libdeflate`** | **~206,000 reads/sec** | **Production Ready** |
| Plain FASTQ | `auto` | ~176,000 reads/sec | Baseline |
| Standard GZIP | `compat` | ~71,000 reads/sec | Fallback |

## Current Status
- **Production Engine**: The Async Prefetcher is active by default for all GZIP inputs.
- **Native Parity**: The pure-Zig `NATIVE_QWD` engine has reached bit-perfect and performance parity with `libdeflate`.
- **Hardware Coverage**: Optimized for Apple Silicon (NEON) and x86_64 (AVX2).
