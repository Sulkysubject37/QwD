# QwD (قَلَّ وَدَلَّ)

![Version](https://img.shields.io/badge/Version-1.1.0--stable-blue?style=flat-square)
![Zig](https://img.shields.io/badge/Language-Zig_0.13.0-orange?logo=zig&logoColor=white)
![SIMD](https://img.shields.io/badge/SIMD-NEON%20%2F%20AVX2-blueviolet?style=flat-square)
![Python](https://img.shields.io/badge/Bindings-Python_3.10+-3776AB?logo=python&logoColor=white)
![R Statistics](https://img.shields.io/badge/Bindings-R_4.5+-276DC3?logo=r&logoColor=white)
![Swift](https://img.shields.io/badge/Dashboard-SwiftUI-F05138?logo=swift&logoColor=white)
![Build Status](https://github.com/Sulkysubject37/QwD/actions/workflows/ci.yml/badge.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-000000?style=flat-square)

QwD is a highly advanced SIMD-vectorized streaming Sequence Analytics Engine. ![QwD Logo](qwd_logo.png)

### Meaning
QwD derives from Arabic:
**قَلَّ وَدَلَّ (qalla wa dalla)**
Meaning: **brevity with clarity**

### Motto
QwD — minimal passes, maximal insight

---

### Project Status (v1.1.0)
QwD has reached a major milestone with the release of **v1.1.0**. This version introduces a fully refactored Columnar SIMD Engine and the debut of the **QwD Dashboard**, a professional macOS interface for laboratory-grade diagnostics.

### QwD Dashboard
A native macOS (SwiftUI) application built for researchers who require instant, visual feedback on sequence quality.
- **Lab Professional Aesthetic**: A high-density, "Apple-minimalist" design optimized for information retrieval at a glance.
- **Scientific Print Engine**: High-fidelity, vector-based PDF export for professional documentation.
- **Real-Time Visuals**: Integrated high-contrast charts for GC Composition, Read Length distribution, and Sequence Entropy.
- **Deep Integration**: Seamlessly bridges the high-performance Zig core with modern macOS UI capabilities.

### Description
QwD is a high-performance streaming analytics engine designed for FASTQ and BAM sequencing data. It delivers real-time diagnostics by performing exhaustive analytics in a single streaming pass, with a core focus on **Scientific Determinism**—guaranteeing bit-identical results regardless of hardware concurrency.

QwD operates in two distinct modes:
1. **Exact Mode (Default)**: Prioritizes 100% precision. Uses exhaustive sequence tracking via HashMaps to ensure every single read is accounted for in duplication and overrepresentation metrics.
2. **Fast Mode (Probabilistic)**: Prioritizes throughput and memory efficiency. Replaces heavy tracking with mathematically-sound sketches (Bloom Filters and MinHash), delivering ~5x speedup.

### Key Features
- **Streaming Core**: O(1) resident memory footprint per thread, capable of processing multi-terabyte datasets without OOM.
- **Phase Q/R Optimized Engine**: Fully vectorized 16x16 transposition kernels and fused bitplane analytics over 32-lane column chunks.
- **Scientific Determinism**: A lock-free aggregation system ensures perfectly reproducible results across any thread count.
- **Vertical SIMD Scanner**: hardware-accelerated newline scanning for 32-lane record boundary detection.
- **Multi-Language Core**: Unified C API exposing `qwd_fastq_qc_fast` for native integration with Python, R, and Swift.

---

### Architecture
The core architecture follows a high-density linear data flow:

**mmap → Vertical Scanner → Parallel Scheduler → Columnar Transpose → Bitplane Kernels → Aggregation**

---

### Installation & Build

#### Prerequisites
- Zig 0.13.0
- Swift 6.0+ (For Dashboard only)

#### Build Core Engine
```bash
# Build Release binary (v1.1.0 Contract)
/usr/local/zig/zig build -Doptimize=ReleaseFast
```

#### Build Dashboard (macOS)
```bash
cd apps/dashboard
swift build -c release
```

---

### CLI Usage
For a detailed guide on subcommands and flags, see the **[CLI Usage Guide](docs/cli_usage.md)**.

- **Exact Mode (Deterministic QC)**: 
  ```bash
  qwd qc --threads 8 reads.fastq
  ```
- **Fast Mode (Probabilistic QC)**: 
  ```bash
  qwd qc --fast --threads 8 reads.fastq
  ```

---

### Python & R Integration

#### Python
```python
import qwd
data = qwd.qc("reads.fastq", fast=True, threads=4)
print(f"Total Reads: {data['stages']['basic_stats']['total_reads']}")
```

#### R
```R
source("bindings/r/R/qwd.R")
metrics <- qwd_qc("reads.fastq", fast = TRUE)
print(metrics$stages$basic_stats$total_reads)
```

---

### Performance Benchmarks (v1.1.0)
On a standard workstation (8 cores):
- **Throughput**: ~1.5M – 2.5M reads/sec (Full QC suite).
- **Peak Throughput**: >5M reads/sec (Core Engine / Minimal Stats).
- **Memory Floor**: ~85MB - 256MB RSS (Hard Cap).

---

### License
Academic Free License (AFL) 3.0

### Author
MD. Arshad (arshad10867c@gmail.com)
