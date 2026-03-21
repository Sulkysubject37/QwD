# QwD ![QwD Logo](qwd_logo.png)

### Meaning
QwD derives from Arabic:
**قَلَّ وَدَلَّ (qalla wa dalla)**
Meaning: **brevity with clarity**

### Motto
QwD — minimal passes, maximal insight

[![QwD CI](https://github.com/Sulkysubject37/QwD/actions/workflows/ci.yml/badge.svg)](https://github.com/Sulkysubject37/QwD/actions/workflows/ci.yml)
[![Python Bindings](https://github.com/Sulkysubject37/QwD/actions/workflows/python-bindings.yml/badge.svg)](https://github.com/Sulkysubject37/QwD/actions/workflows/python-bindings.yml)
[![R Bindings](https://github.com/Sulkysubject37/QwD/actions/workflows/r-bindings.yml/badge.svg)](https://github.com/Sulkysubject37/QwD/actions/workflows/r-bindings.yml)

---

### Description
QwD is a high-performance streaming analytics engine designed for FASTQ and BAM sequencing data. It delivers real-time diagnostics by performing exhaustive analytics in a single streaming pass, with a core focus on **Scientific Determinism**—guaranteeing bit-identical results regardless of hardware concurrency.

QwD operates in two distinct modes:
1. **Exact Mode (Default)**: Prioritizes 100% precision. Uses exhaustive sequence tracking via HashMaps to ensure every single read is accounted for in duplication and overrepresentation metrics. This mode is compute-intensive but provides the definitive scientific baseline.
2. **Fast Mode (Probabilistic)**: Prioritizes throughput and memory efficiency. Replaces heavy tracking with mathematically-sound sketches (Bloom Filters and MinHash), delivering ~5x speedup with minimal loss in precision.

### Key Features
- **Streaming Core**: O(1) resident memory footprint per thread, capable of processing multi-terabyte datasets without OOM.
- **Scientific Determinism**: A lock-free aggregation system ensures that results are perfectly reproducible across any thread count, solving the "non-deterministic race" issue common in parallel bioinformatics tools.
- **Phase Q Columnar Engine**: Fully vectorized k-mer counting and fused bitplane analytics over 32-lane column chunks.
- **Vertical SIMD Scanner**: 32-lane record boundary detection using hardware-accelerated newline scanning.
- **In-Register Transposition**: ASCII rows are transposed to columnar blocks in L1 cache using recursive 8x8 and 16x16 shuffle kernels.
- **Language Bindings**: Native FFI support for Python (ctypes) and R, enabling high-performance analytics within standard bioinformatics environments.

---

### Architecture
The core architecture follows a high-density linear data flow:

**mmap → Vertical Scanner → Parallel Scheduler → Columnar Transpose → Bitplane Kernels → Aggregation**

Example pipeline:
```text
FASTQ stream (mmap)
   ↓
SIMD Scanner (Record Detection)
   ↓
[ Basic Stats | GC Content | k-mer Spectrum | Entropy | N50 | Duplication ]
   ↓
Structured Output (JSON/NDJSON)
```

---

### Installation & Build

#### Prerequisites
- Zig 0.13.0 (Strictly enforced)

#### Build from Source
```bash
# Install Zig via script (if not present)
./scripts/install_zig.sh

# Build Release binary
zig build -Doptimize=ReleaseFast
```

The binary will be available at `./zig-out/bin/qwd`.

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
- **BAM Alignment Stats**: 
  ```bash
  qwd bamstats alignments.bam
  ```
- **Streaming NDJSON Output**: 
  ```bash
  qwd qc --ndjson reads.fastq > metrics.ndjson
  ```

---

### Python & R Integration

#### Python
```python
import qwd
data = qwd.qc("reads.fastq")
print(f"Total Reads: {data['basic_stats']['total_reads']}")
```

#### R
```R
library(qwd)
metrics <- qwd_qc("reads.fastq")
summary(metrics)
```

---

### Performance Benchmarks (Phase Q)
On a standard workstation (8 cores):
- **Throughput**: ~1.3M – 2.1M reads/sec (Full QC suite).
- **Peak Throughput**: >5M reads/sec (Core Engine / Minimal Stats).
- **Memory Floor**: ~85MB - 256MB (Configurable hard cap).

---

### License
Academic Free License (AFL) 3.0

### Author
MD. Arshad (arshad10867c@gmail.com)
