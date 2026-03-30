# QwD CLI Usage Guide

QwD provides a high-density streaming interface for bioinformatics analytics. This guide covers all subcommands and configuration flags.

## Global Options

These flags can be applied to any subcommand:

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--threads N` | Number of worker threads for parallel processing. | CPU Count |
| `--mode <type>` | Analytical strategy: `exact` (deterministic) or `approx` (heuristic). | `exact` |
| `--gzip-mode <m>` | Decompression engine: `auto`, `libdeflate`, `qwd`, `compat`. | `auto` |
| `--json` | Output aggregated results as a single JSON object. | Off (Text) |
| `--ndjson` | Output results in Newline Delimited JSON format. | Off |
| `--max-memory N` | Hard memory limit in Megabytes. | 1024 MB |
| `--perf` | Print detailed performance metrics (throughput, CPU time). | Off |
| `--quiet` | Minimize output verbosity. | Off |

---

## Analytical Modes (`--mode`)

QwD separates **Analytical Precision** from **Decompression Speed**.

### 1. Exact Mode (`--mode exact`)
- **Philosophy**: Scientific Determinism.
- **Precision**: 100%. Bit-identical results regardless of thread count.
- **Behavior**: Uses exhaustive data structures (e.g., full HashMaps for duplication).
- **Use Case**: Publication-grade results, final data submission.

### 2. Approximate Mode (`--mode approx`)
- **Philosophy**: Hyperscale Heuristics.
- **Precision**: >99% (Statistical bound).
- **Behavior**: Uses sketches and probabilistic structures (Bloom Filters, MinHash). Employs `mmap` for zero-copy uncompressed I/O.
- **Use Case**: Real-time streaming, multi-terabyte datasets, quick diagnostic checks.

---

## Decompression Engines (`--gzip-mode`)

Integrated GZIP is powered by an **Async Prefetch Engine** that overlaps decompression with analysis.

| Engine | Description |
| :--- | :--- |
| **`auto`** | (Default) Detects BGZF and uses the fastest available path. |
| **`libdeflate`** | Uses `libdeflate` SIMD (AVX2/NEON) kernels. Best for production. |
| **`qwd`** | Uses the **Pure-Zig Native Engine**. Performance parity with `libdeflate`. |
| **`compat`** | Standard library fallback. Use only for non-blocked, legacy GZIP files. |

---

## Subcommands

### 1. `qc`
Runs the full suite of Quality Control analytics (FASTQ).
```bash
qwd qc reads.fastq.gz --threads 8 --mode exact --gzip-mode qwd
```

### 2. `bamstats`
Alignment and coverage analytics for BAM files.
```bash
qwd bamstats alignments.bam --json
```

### 3. `entropy` | `n50` | `quality-decay` | `adapter-detect`
Focused analysis subcommands for specific FASTQ metrics.

### 4. `pipeline`
Runs a custom analytical pipeline defined in a JSON file.
```bash
qwd pipeline config.json reads.fastq
```
