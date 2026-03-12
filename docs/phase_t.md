# Phase T: Stable Interface Layer and Language Bindings

## Overview
Phase T introduces a stable interface layer for the QwD engine, enabling integration with high-level languages like Python and R while preserving the core engine's performance and determinism.

## Stable CLI Specification
The QwD CLI is frozen with the following stable commands:
- `qwd qc <fastq>`: Comprehensive FASTQ Quality Control.
- `qwd fastq-stats <fastq>`: Alternative for QC.
- `qwd bamstats <bam>`: BAM alignment diagnostics.
- `qwd pipeline <stages> <input>`: Custom analytical pipelines.
- `qwd run --config <config>`: Pipeline execution via JSON configuration.

### Global Flags
- `--threads <N>`: Set number of worker threads (default: 1).
- `--json`: Output final metrics in structured JSON format.
- `--ndjson`: Output incremental metrics in Newline Delimited JSON.
- `--quiet`: Suppress all non-essential output.
- `--version`: Print version information.

## Structured Output System
The structured output layer wraps existing metrics to support:
- **Text**: Standard human-readable reports.
- **JSON**: Machine-readable full reports.
- **NDJSON**: Streaming metrics emitted during execution.

## Language Bindings Architecture
QwD exposes a stable C ABI, which is used by Python and R bindings.

```text
QwD Core (Zig)
     ↓
   C ABI (Shared Library)
     ↓
Python (ctypes) / R (dyn.load) / CLI
```

## C ABI Interface
The `libqwd` shared library exports functions that return JSON strings, avoiding the need to expose internal memory layouts or pointer-heavy structures to foreign languages.

## Python Bindings
The `qwd` Python package provides a native feel:
```python
import qwd
metrics = qwd.qc("data.fastq")
print(metrics["gc_ratio"])
```

## R Bindings
The R interface allows seamless integration into bioinformatics workflows:
```R
library(qwd)
stats <- qwd_bamstats("alignments.bam")
```

## CI/CD Validation
Binding integrity is verified across Ubuntu, macOS, and Windows via automated tests that validate output against formal JSON Schemas.
