# QwD CLI Usage Guide

QwD provides a high-density streaming interface for bioinformatics analytics. This guide covers all subcommands and configuration flags.

## Global Options

These flags can be applied to any subcommand:

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--threads N` | Number of worker threads for parallel processing. | CPU Count |
| `--mode <type>` | Execution mode: `exact` or `fast`. | `exact` |
| `--fast` | Shorthand for `--mode fast`. | Off |
| `--json` | Output aggregated results as a single JSON object. | Off (Text) |
| `--ndjson` | Output results in Newline Delimited JSON format. | Off |
| `--max-memory N` | Hard memory limit in Megabytes. | 1024 MB |
| `--perf` | Print detailed performance metrics (throughput, CPU time). | Off |

---

## Subcommands

### 1. `qc` (or `fastq-stats`)
Runs the full suite of Quality Control analytics.
```bash
qwd qc reads.fastq --threads 8 --mode exact
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

### 5. `quality-decay`
Analyzes how sequencing quality drops across the read length.
```bash
qwd quality-decay reads.fastq
```

### 6. `adapter-detect`
Identifies presence of common adapter sequences in the 3' ends.
```bash
qwd adapter-detect reads.fastq
```

### 7. `pipeline`
Runs a custom analytical pipeline defined in a JSON file.
```bash
qwd pipeline config.json reads.fastq
```
**Example `config.json`:**
```json
{
  "pipeline": ["basic-stats", "gc", "entropy"]
}
```

---

## Execution Modes

### Exact Mode (Default)
- **Philosophy**: Scientific Determinism.
- **Precision**: 100%.
- **Behavior**: Uses full HashMaps to track every unique sequence for duplication and overrepresentation metrics. 
- **Use Case**: Final publication-grade results, small to medium datasets.

### Fast Mode (`--fast`)
- **Philosophy**: Probabilistic Speed.
- **Precision**: >99%.
- **Behavior**: Replaces exact tracking with Bloom Filters and MinHash sketches. Uses `mmap` for zero-copy I/O.
- **Use Case**: Real-time streaming, multi-terabyte datasets, quick diagnostic checks.
