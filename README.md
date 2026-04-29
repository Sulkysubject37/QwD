# QwD (قَلَّ وَدَلَّ): The Genomic Command Center
![Version](https://img.shields.io/badge/Version-1.3.0--Raja--Reform-blueviolet?style=flat-square)
![Build](https://github.com/Sulkysubject37/qwd/actions/workflows/native_performance.yml/badge.svg)
![License](https://img.shields.io/badge/License-AFL--3.0-green?style=flat-square)

QwD is a high-performance, SIMD-vectorized streaming Sequence Analytics Engine for genomic data. ![QwD Logo](qwd_logo.png)

### Meaning
QwD derives from Arabic:
**قَلَّ وَدَلَّ (qalla wa dalla)**
Meaning: **brevity with clarity**

---

### Project Status (v1.3.0 Raja Reform)
The "Raja Reform" milestone (v1.3.0) marks the transition to a **Pure Agnostic Core**, building upon the "Zero-Overhead Security" and "Scientific Formalization" established in previous hardened releases. By decoupling the computational engine from platform-specific I/O and scheduling, QwD now runs with bit-exact consistency across Desktop and Mobile, ensuring elite computational performance without compromising data integrity.

### Key Features
- **Pure Agnostic Core**: Zero dependencies on `std.Thread` or `std.posix` in the computational kernels.
- **Active Control Dashboard (macOS)**: Interactive biological control surface for real-time parameter injection (5'/3' Trimming, Quality Filtering, Adapter Removal) via a JSON-Configured Reactive Engine.
- **Phase Sec-Zero Architecture**: Implemented hardware-level protection mechanisms (Bitplane Mutex Guard) and hardened decompression ceilings (32x expansion gate) to neutralize malicious genomic payloads.
- **Scientific Formalization**: Verified $R^2 = 1.0$ against legacy baselines (EXACT mode) and $<0.05\%$ MAPE for hardware-level sampling (APPROX mode).
- **Hardened Parallel Scheduler**: Dual-pool worker model for truly parallel asynchronous decompression and analysis with zero-overhead block-wait backoff.
- **Vertical SIMD & Bitplane Core**: Converts genomics data into parallel bit-matrices, utilizing 16x16 register-based transposition (ARM NEON / x86 AVX2) and reducing analytical complexity to **O(N/64)** using hardware popcount.
- **Unified C-ABI**: A hardened binary interface for high-level universal integration (Swift, Android/Sokol).
- **Unified JSON Reporting**: Standardized schema parity providing comprehensive QC metrics (Basic Stats, GC Dist, N-Stats, Length Dist, Quality Dist, Nucleotide Comp) across FASTQ, BAM, Python, R, and Swift.

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
zig build -Doptimize=ReleaseFast
```

### Quick Start
- **CLI**: `qwd qc reads.fastq.gz --threads 8 --mode exact`
- **Python**: `import qwd; metrics = qwd.qc("reads.fastq.gz", threads=8, approx=False)`
- **R**: `library(qwd); res <- qwd_qc("reads.fastq.gz", threads=8, approx=FALSE)`
- **Workstation**: `zig build run-workstation`

---

## 📱 Future: Android Native
Phase 1.3.x focuses on the **Android Native APK**. Using a unified Sokol + Zig stack, the Genomic Command Center provides laboratory-grade analysis directly on mobile devices without JNI overhead.

---

### Documentation
- **[Architecture: Hardened Parallelism](docs/native_qwd_engine.md)**
- **[Phase Tax-ed: Taxonomic Screening & HD Visuals](docs/phase_taxed.md)**
- **[Phase Sec-Zero: Hardened Security](docs/phase_sec_zero.md)**
- **[Phase P: Universal GZIP Engine](docs/phase_p.md)**
- **[CLI Usage Guide](docs/cli_usage.md)**
- **[Dashboard Setup](apps/dashboard/README.md)**

### License
Academic Free License ("AFL") v. 3.0

### Author
MD. Arshad (arshad10867c@gmail.com)
Dept. of Computer Science, Jamia Millia Islamia.
