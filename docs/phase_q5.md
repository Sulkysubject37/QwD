# Phase Q.5: Interface & Contract Stabilization (v1.0.0)

## Overview
Phase Q.5 establishes the definitive, versioned baseline for the QwD engine. After the massive columnar SIMD rewrites of Phase Q, this phase freezes the external API boundaries, making QwD a production-grade bioinformatics dependency.

This document formally introduces **v1.0.0**.

## 1. CLI Contract
The Command Line Interface is strictly frozen. No arguments will be renamed, removed, or ambiguously defaulted.

### Stable Commands:
- `qwd qc <input-fastq>`
- `qwd bamstats <input-bam>`
- `qwd pipeline <config.json> <input-fastq>`

### Core Flags:
- `--mode <exact|fast>`: Execution algorithm.
  - **Exact**: 100% deterministic baseline using full hash-mapping.
  - **Fast**: Probabilistic execution using bounded MinHash/Bloom filter strategies.
- `--threads <N>`: Explicit worker count.
- `--max-memory <MB>`: Hard memory allocation ceiling.
- `--json`: Output strict, flat JSON objects.
- `--ndjson`: Output incrementally streamed structural records.
- `--quiet`: Minimize text.
- `--version`: Emits `QwD v1.0.0`.

## 2. JSON Schema Specifications
QwD guarantees payload stability. All computational results adhere rigorously to predefined JSON Schemas located under `/schemas/`.
- `schemas/fastq_qc.schema.json`: Enforces static keys for all FASTQ stages.
- `schemas/bam_stats.schema.json`: Enforces static keys for all BAM outputs.
- `schemas/pipeline.schema.json`: Defines valid custom inputs.

## 3. Streaming NDJSON Target
For massive datasets or cloud integration, `--ndjson` bypasses the wait time by incrementally streaming `{"reads_processed": <count>}` without corrupting the final schema output.

## 4. Sub-System Guarantees
1. *Memory Consistency*: Exact mode memory spikes trigger graceful, autonomous stage throttling to obey `--max-memory`. Fast mode statically bounds absolute analytical footprint to <32MB.
2. *C ABI Concurrency*: Native libraries built via `x86_64-windows-gnu` and OSX/Linux GCC are cross-language compatible. C-strings are safely managed through rigorous `qwd_free_string` calls.
3. *System Determinism*: Bit-identical math executes sequentially and coalesces lockless worker outputs transparently. No thread configuration alters the outcome.

**Version**: `1.0.0`
