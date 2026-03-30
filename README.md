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

---

### Project Status (v1.1.0)
QwD v1.1.0 introduces the **Universal GZIP Engine**, delivering integrated decompression that is **18% faster** than reading uncompressed files. This version also debuts the **QwD Dashboard**, a professional macOS interface for laboratory-grade diagnostics.

### Key Features
- **Async GZIP Prefetcher**: A background decompression engine that overlaps I/O with analysis, reaching **>200k reads/sec** on integrated GZIP data.
- **Native "Bit-Sieve" Core**: A pure-Zig DEFLATE implementation achieving performance parity with `libdeflate`.
- **Orthogonal Execution**: Explicit separation between Analytical Precision (`exact` vs `approx`) and Decompression Engine (`auto`, `libdeflate`, `qwd`, `compat`).
- **Phase Q/R Optimized Engine**: Vectorized 16x16 transposition kernels and 32-lane column chunks.
- **Scientific Determinism**: Guaranteed bit-identical results across all thread counts.
- **Multi-Language Bindings**: Full support for Python, R, and Swift with unified feature sets.

---

### Analytical Modes (`--mode`)
1. **Exact Mode (Default)**: 100% precision. Uses exhaustive tracking for final publication-grade results.
2. **Approx Mode**: Probabilistic acceleration using Bloom Filters and MinHash, delivering massive throughput for terabyte-scale diagnostics.

---

### Performance (1M Reads Benchmark)
| Format | Engine | Throughput | vs Plain |
| :--- | :--- | :--- | :--- |
| **BGZF GZIP** | **Native Async** | **~207,000 reads/sec** | **1.18x** |
| Plain FASTQ | Direct I/O | ~176,000 reads/sec | 1.00x |
| Standard GZIP | Compat Fallback | ~71,000 reads/sec | 0.40x |

---

### Installation & Build
```bash
/usr/local/zig/zig build -Doptimize=ReleaseFast
```

### Quick Start
- **CLI**: `qwd qc reads.fastq.gz --mode exact`
- **Python**: `qwd.qc("reads.fastq.gz", gzip_mode="qwd")`
- **R**: `qwd_qc("reads.fastq.gz", approx=TRUE)`

---

### Documentation
- **[CLI Usage Guide](docs/cli_usage.md)**
- **[Phase P: Universal GZIP Engine](docs/phase_p.md)**
- **[Dashboard Setup](apps/dashboard/README.md)**

### License
Academic Free License (AFL) 3.0

### Author
MD. Arshad (arshad10867c@gmail.com)
