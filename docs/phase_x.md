# Phase X: Pipeline Engine and Preprocessing

## Overview
Phase X extends the QwD engine to support chained preprocessing and analytics in a single streaming pass.

## Pipeline Engine
The `core/pipeline` module allows for constructing a sequential chain of stages based on user configuration.

## Preprocessing Stages
1. **Trim Stage**: Removes adapter sequences from read suffixes.
2. **Filter Stage**: Discards reads based on an average quality threshold.
3. **k-mer Stage**: Computes k-mer frequency using a deterministic array-based counter (4^k).

## Filtering Behavior
Each stage now returns a boolean:
- `true`: Continue processing.
- `false`: Discard the read and stop downstream processing for it.

## Architecture Diagram
```text
FASTQ
  ↓
Parser
  ↓
Scheduler
  ↓
Trim → Filter → QC → GC → Length → k-mer
  ↓
Metrics
```

The CLI `pipeline` command enables flexible stage selection.
```bash
qwd pipeline trim,filter,qc example.fastq
```
All operations execute sequentially on each read during streaming, maintaining a bounded memory footprint.
