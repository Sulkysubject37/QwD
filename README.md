# QwD (قَلَّ وَدَلَّ)

![Version](https://img.shields.io/badge/Version-1.1.0--stable-blue?style=flat-square)
![Zig](https://img.shields.io/badge/Language-Zig_0.13.0-orange?logo=zig&logoColor=white)
![SIMD](https://img.shields.io/badge/SIMD-NEON%20%2F%20AVX2-blueviolet?style=flat-square)
![Python](https://img.shields.io/badge/Bindings-Python_3.10+-3776AB?logo=python&logoColor=white)
![R Statistics](https://img.shields.io/badge/Bindings-R_4.5+-276DC3?logo=r&logoColor=white)
![Swift](https://img.shields.io/badge/Dashboard-SwiftUI-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-000000?style=flat-square)

### Build Status
| Core Engine | Bindings & Ecosystem | SwiftUI Dashboard |
| :--- | :--- | :--- |
| [![Core CI](https://github.com/Sulkysubject37/QwD/actions/workflows/core.yml/badge.svg)](https://github.com/Sulkysubject37/QwD/actions/workflows/core.yml) | [![Ecosystem CI](https://github.com/Sulkysubject37/QwD/actions/workflows/bindings.yml/badge.svg)](https://github.com/Sulkysubject37/QwD/actions/workflows/bindings.yml) | [![Dashboard CI](https://github.com/Sulkysubject37/QwD/actions/workflows/dashboard.yml/badge.svg)](https://github.com/Sulkysubject37/QwD/actions/workflows/dashboard.yml) |

QwD is a high-performance, SIMD-vectorized streaming Sequence Analytics Engine for genomic data. ![QwD Logo](qwd_logo.png)

### Meaning
QwD derives from Arabic:
**قَلَّ وَدَلَّ (qalla wa dalla)**
Meaning: **brevity with clarity**

---

### Project Status (v1.1.0-stable Hardened)
QwD v1.1.0 has been hardened for production use, focusing on scale-invariant stability and parallel efficiency. This release resolves critical multi-threaded memory hazards, implements a zero-overhead block-wait backoff, and unifies the reporting engine across the ecosystem. The system is verified stable for files exceeding **10 Million reads** in high-precision mode.

### Key Features
- **Hardened Parallel Engine**: Resolved VTable and stack-bound hazards, ensuring absolute stability during multi-threaded analysis.
- **Ordered Parallel BGZF Analysis**: A truly parallel double-pipeline that offloads both decompression and analytical processing to the worker pool.
- **Vertical SIMD & Bitplane Core**: Converts genomics data into parallel bit-matrices, reducing analytical complexity to **O(N/64)** using hardware popcount.
- **Hurricane-Spin Protection**: Replaced tight `yield()` loops with smart backoff, reducing idling CPU usage from 250% to **<5%**.
- **Unified JSON Reporting**: Standardized schema parity across the entire ecosystem (FASTQ, BAM, Python, R, and Swift).
- **Scale-Invariant Memory**: Heap-allocated persistence for analytical stages, supporting long-read sequences up to 1MB/read.

---

### Performance Metrics

#### 1. Peak Decompression Throughput (1M Reads, Single-Core)
| Format | Engine | Throughput | vs Plain |
| :--- | :--- | :--- | :--- |
| **BGZF GZIP** | **libdeflate (SIMD)** | **~5,830,000 reads/sec** | **1.04x** |
| **BGZF GZIP** | **QwD Native (Zig)** | **~5,290,000 reads/sec** | **0.94x** |
| Plain FASTQ | Direct I/O | ~5,590,000 reads/sec | 1.00x |
| Standard GZIP | Compat Fallback | ~3,110,000 reads/sec | 0.55x |

#### 2. End-to-End Analysis (1M Reads, Multi-threaded)
| Stage | Mode | Threads | Time | Throughput |
| :--- | :--- | :--- | :--- | :--- |
| **FASTQ QC** | **EXACT** | **8** | **0.80s** | **~1,250,000 reads/sec** |
| **BAM Stats** | **EXACT** | **1** | **~0.2s** | **~250,000 reads/sec** |

*Note: QwD overlaps decompression with analysis, making compressed processing effectively "free" relative to raw I/O. Throughput scales linearly with available CPU cores.*

---

### Installation & Build
```bash
/usr/local/zig/zig build -Doptimize=ReleaseFast
```

### Quick Start
- **CLI**: `qwd qc reads.fastq.gz --threads 8 --mode exact`
- **Python**: `import qwd; metrics = qwd.qc("reads.fastq.gz", threads=8, approx=False)`
- **R**: `library(qwd); res <- qwd_qc("reads.fastq.gz", threads=8, approx=FALSE)`

---

### Documentation
- **[Architecture: Hardened Parallelism](docs/native_qwd_engine.md)**
- **[Phase P: Universal GZIP Engine](docs/phase_p.md)**
- **[CLI Usage Guide](docs/cli_usage.md)**
- **[Dashboard Setup](apps/dashboard/README.md)**

### License
Academic Free License (AFL) 3.0

### Author
MD. Arshad (arshad10867c@gmail.com)
