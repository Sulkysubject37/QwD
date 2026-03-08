# Phase Y: Streaming Analytics Stages

## Overview
Phase Y introduced modular analytics stages that operate in a single streaming pass.

## Stage Interface
Each stage implements a standard interface:
- `init()`: Initialize state.
- `process(read)`: Process a single read incrementally.
- `finalize()`: Compute final metrics.
- `report()`: Output results to console.

## Implemented Stages
1. **QC Stage**: Computes total reads, total bases, and mean PHRED quality.
2. **GC Stage**: Computes GC ratio using incremental base counting.
3. **Read Length Stage**: Tracks min, max, and mean read length.

## Architecture Diagram
```text
FASTQ
  ↓
Parser
  ↓
Scheduler
  ↓
QC | GC | Length
  ↓
Metrics
```
The metrics aggregation occurs by collecting reports from all registered stages. This process ensures that processing only requires a single pass over the FASTQ data.
