# QwD CLI Usage Guide

QwD provides a high-density streaming interface for bioinformatics analytics. This guide covers all subcommands and configuration flags.

## Global Options

These flags can be applied to any subcommand:

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--threads N` | Number of worker threads for parallel processing. | CPU Count |
| `--mode <type>` | Execution mode: `exact` or `approx`. | `exact` |
| `--fast` | Alias for `--mode approx`. | Off |
| `--gzip-backend <m>` | Engine: `auto`, `native`, `libdeflate`, `compat`. | `auto` |
| `--json` | Output aggregated results as a single JSON object. | Off (Text) |
| `--max-memory N` | Hard memory limit in Megabytes. | 1024 MB |
| `--perf` | Print detailed performance metrics. | Off |

---

## Gzip & Compression Options

QwD features a native parallel decompression engine designed for high-performance processing of compressed genomic data.

- `auto`: (Recommended) Automatically probes the file. If it detects a BGZF (Blocked GNU Zip Format) file, it enables full parallel decompression. If standard GZ, it falls back to a fast sequential stream.
- `native`: Forces the use of the built-in pure-Zig decompression engine.
- `libdeflate`: Forces the use of SIMD-accelerated `libdeflate`. Recommended for maximum throughput on x86_64 and ARM64.
- `compat`: Uses a robust sequential path for standard GZ files while still parallelizing the downstream analysis stages.

---

## Subcommands

### 1. `qc`
Runs the full suite of Quality Control analytics.
```bash
qwd qc reads.fastq.gz --threads 8 --gzip-backend auto
```
**Included Stages:**
- Basic Stats (Reads, Bases, Mean Length)
- Per-Base Quality
- Nucleotide Composition
- GC Distribution
- Length Distribution
- N-Statistics (N50, etc.)
- Sequence Entropy
- K-mer Spectrum (k=5)
- Overrepresented Sequences
- Duplication Rate
- Adapter Detection

### 2. `bamstats`
Alignment and coverage analytics for BAM files.
```bash
qwd bamstats alignments.bam --json
```

### 3. `entropy`
Focused sequence complexity analysis.
```bash
qwd entropy reads.fastq
```

### 4. `n50`
Calculates assembly-style N-statistics (N10 through N90).
```bash
qwd n50 reads.fastq
```

### 5. `adapter-detect`
Identifies presence of common adapter sequences in the 3' ends.
```bash
qwd adapter-detect reads.fastq
```

### 6. `pipeline`
Runs a custom analytical pipeline defined in a JSON file.
```bash
qwd pipeline config.json reads.fastq.gz --threads 16 --gzip-backend libdeflate
```
**Example `config.json`:**
```json
{
  "pipeline": ["basic_stats", "gc_distribution", "entropy"]
}
```

---

## Execution Modes

### Exact Mode (Default)
- **Philosophy**: Scientific Determinism.
- **Precision**: 100% bit-exact.
- **Behavior**: Processes every single base and quality score. Uses full HashMaps for exact sequence tracking.
- **Use Case**: Final publication-grade results, clinical diagnostics.

### Approx Mode (`--fast`)
- **Philosophy**: Probabilistic Scaling.
- **Precision**: >99% (Statistical expectation).
- **Behavior**: Uses memory-mapped I/O and probabilistic sketching.
- **Use Case**: Terabyte-scale screening, real-time sequencing monitoring.
