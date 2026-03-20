# QwD

### Meaning
QwD derives from Arabic:
**قَلَّ وَدَلَّ (qalla wa dalla)**
Meaning: **brevity with clarity**

### Motto
QwD — minimal passes, maximal insight

---

### Description
QwD is a high-performance streaming analytics engine designed for FASTQ and BAM sequencing data. It is capable of producing real-time diagnostics by performing multiple analytics in a single streaming pass.

QwD focuses on:
- **Streaming processing**: No need to load the entire dataset into memory.
- **Deterministic memory**: Bounded memory usage regardless of dataset size.
- **Modular analytics stages**: Composable stages for flexible analysis pipelines.
- **Hardware Acceleration**: SIMD-optimized inner loops (GC counting, PHRED summing) providing 3x-7x speedups.
- **Parallel Execution**: Multithreaded processing while maintaining bit-exact reproducibility.
- **Phase Q Columnar Engine**: Fully vectorized k-mer counting and fused bitplane analytics over 32-lane column chunks.
- **Language Bindings**: Production-ready Python (cffi/ctypes) and R native FFI bindings for streamlined bioinformatics workflows.

---

### Architecture Overview
The core architecture follows a linear data flow:

**Input → Parser → Scheduler → Stages → Aggregator → Output**

Example pipeline:
```text
FASTQ stream
   ↓
Parser
   ↓
[QC | GC | Length | k-mer | Entropy | N50]
   ↓
Metrics
```

---

### CLI Usage
- **FASTQ QC**: `qwd qc reads.fastq`
- **BAM Stats**: `qwd bamstats alignments.bam`
- **Custom Pipeline**: `qwd pipeline trim,filter,qc reads.fastq`
- **JSON Config**: `qwd run --config pipeline.json reads.fastq`
- **Parallel Mode**: Use `--threads N` with any command.

---

### Repository Layout
- `core/`: Core engine components (parser, scheduler, allocator, SIMD, parallel).
- `stages/`: Modular analytics stages (QC, GC, read length, alignment, etc.).
- `io/`: Input/Output handlers for different formats (BAM, FASTQ).
- `bindings/`: Language bindings for Python and R.
- `apps/`: End-user applications, including a CLI and dashboard.
- `scripts/`: Utility scripts for development and deployment.
- `benchmarks/`: Performance measurement suite.
- `tests/`: Comprehensive test suite (unit, performance, reproducibility).
- `docs/`: Project documentation.

---

### Development
To install the Zig compiler, run:
```bash
./scripts/install_zig.sh
```
Then verify the installation:
```bash
zig version
```

### Build
To build the project:
```bash
zig build
```

---

### License
Academic Free License (AFL) 3.0

### Author
MD. Arshad (arshad10867c@gmail.com)
