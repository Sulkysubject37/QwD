# Native QwD Decompression Engine: Technical Reference

## Overview
The Native QwD Engine is a high-density implementation of the DEFLATE compression algorithm (RFC 1951), specialized for genomics data. It is designed to achieve performance parity with industry-standard C libraries while maintaining a zero-dependency, memory-safe footprint.

## Core Components

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

## Parallel Architecture (Phase P.2)

### Ordered Parallel Decompression
To break the serial bottleneck of Gzip, QwD implements an **Ordered Parallel** pipeline in `ParallelScheduler`:
- **Feeder Thread**: Reads raw BGZF blocks from disk and assigns them to worker slots.
- **Decompression Workers**: Parallelly decompress blocks using `libdeflate` or the Native QwD engine.
- **Proxy Stitche**: Stitches decompressed blocks back into a continuous stream, ensuring that FASTQ records spanning block boundaries are parsed with **100% accuracy**.
- **Atomic Synchronization**: Uses `claimed` and `ready` atomic flags to manage buffer ownership across the pipeline without mutex contention.

### Format-Agnostic Probing
QwD features a smart probe (`isBgzf`) that inspects the first 20 bytes of a Gzip member for the `BC` (Block Click) extra field.
- **Path Selection**: Automatically chooses full parallel decompression for BGZF files or async prefetch sequential decompression for standard GZ files.

## Performance Profile (1M Reads)
| Backend | Throughput | Memory Overhead |
| :--- | :--- | :--- |
| **libdeflate (SIMD C)** | **~5.8M reads/sec** | ~2MB RSS per thread |
| **QwD Native (Zig)** | **~5.3M reads/sec** | ~2MB RSS per thread |
| **Standard GZ (Compat)** | **~3.1M reads/sec** | ~4MB RSS total |

## Future: Fused Decompression
The roadmap includes **Fused Decompression (DTB)**. This will allow the `DeflateEngine` to decompress symbols directly into the 2-bit DNA bitplanes, bypassing the ASCII string stage entirely, projected to reach **>10M reads/sec**.
