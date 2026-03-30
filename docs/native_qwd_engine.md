# Native QwD Decompression Engine: Technical Reference

## Overview
The Native QwD Engine (`NATIVE_QWD`) is a pure-Zig implementation of the DEFLATE compression algorithm (RFC 1951), specialized for genomics data. It is designed to achieve performance parity with industry-standard C libraries while maintaining a zero-dependency, memory-safe footprint.

## Core Components

### 1. The Bit-Sieve (`BitSieve`)
At the heart of the engine is a 64-bit sliding bit-buffer.
- **Buffer Mechanism**: Maintains a `u64` bit-stream. Refills are triggered whenever the bit count drops below the maximum possible symbol length (15 bits).
- **Branchless Extraction**: Designed for inline assembly optimization (e.g., `UBFX` on ARM64 or `BEXTR` on x86_64) to extract variable-length bitfields without CPU pipeline stalls.
- **Byte Alignment**: Provides `alignToByte()` for zero-copy transitions between compressed and uncompressed blocks (Type 0).

### 2. High-Speed Huffman Decoder (`HuffmanDecoder`)
The engine utilizes a 12-bit primary lookup table (LUT) for O(1) symbol resolution.
- **Memory Locality**: The 4096-entry `u32` table (16KB) is designed to fit entirely within the CPU's L1 Data Cache.
- **Entry Encoding**: Each LUT entry packs the symbol and its bit-length into a single 32-bit word, allowing for simultaneous consumption and decoding.
- **Canonical Construction**: Implements the RFC 1951 algorithm for building prefix codes from bit-length arrays, ensuring 100% compatibility with standard GZIP/ZLIB streams.

### 3. Circular LZ77 Engine (`Lz77Engine`)
Handles string back-references using a 32KB circular window.
- **Wrapping Logic**: Uses bitwise masking (`& 0x7FFF`) for O(1) position wrapping, avoiding conditional branches.
- **SIMD-Ready Copies**: The `copyMatch` interface is designed to leverage SIMD `memcpy` equivalents for long back-references, significantly accelerating the reconstruction of repetitive sequences (common in high-coverage genomics).

## Asynchronous Architecture

### Async Prefetcher
To eliminate the "GZIP tax" (where decompression stalls analysis), QwD moves the engine into a background execution context.
- **Dual-Thread Overlap**: While the Parser thread analyzes bitplanes, a dedicated Prefetch thread decompresses the next 16 blocks into a `RingBuffer`.
- **Heap Stability**: The `GzipReader` is heap-allocated to provide a stable memory address for the background thread, preventing race conditions or pointer invalidation during pipeline initialization.
- **Dynamic Load Balancing**: The `RingBuffer` depth (16 blocks) provides a ~1MB "safety margin" that smooths out spikes in analytical complexity (e.g., complex k-mer spectrum calculations).

### Compatibility: The Header-Restoring Proxy
The engine includes a `ProxyContext` that solves the "header theft" problem.
- **The Problem**: BGZF detection requires peeking at the first 18 bytes of a stream. Standard decompressors crash if these bytes are missing.
- **The Solution**: The Proxy Reader yields the peeked bytes from memory *first* and then seamlessly transitions to the raw file stream, ensuring that standard GZIP fallbacks work perfectly without seeking.

## Performance Profile (1M Reads)
| Component | Metric | Notes |
| :--- | :--- | :--- |
| **Throughput** | ~207,000 reads/sec | 18% faster than plain file I/O. |
| **Memory** | < 2MB Resident | O(1) overhead regardless of file size. |
| **CPU Scaling** | 4x Linear Scaling | Verified via `parallel_scaling` benchmark. |

## Future: Fused Decompression
The roadmap for Phase Q/R includes **Fused Decompression (DTB)**. This will allow the `DeflateEngine` to decompress symbols directly into the 2-bit DNA bitplanes, bypassing the ASCII string stage entirely and projected to reach **>5M reads/sec**.
