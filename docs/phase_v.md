# Phase V: Complete FASTQ QC and BAM Analytics

## Overview
Phase V completes the diagnostic capabilities of QwD by implementing a full suite of FASTQ QC stages and introducing BAM alignment diagnostics. All processing operates in a single, memory-deterministic streaming pass.

## FASTQ QC Architecture
The FASTQ pipeline extends the previous stages to support:
- Basic Read Statistics
- Per-base Quality Metrics
- Per-base Nucleotide Composition
- Global GC Content & GC Per-read Distribution
- Read Length Distribution & N-Statistics
- Sequence Entropy
- K-mer Spectrum
- Overrepresented Sequences
- Duplication Rate
- Adapter Detection

### FASTQ Pipeline Diagram
```text
FASTQ
  ↓
Parser
  ↓
Scheduler
  ↓
[ Basic Stats | Per-base Quality | Nucleotide Comp | GC | Length Dist | N-Stats | Entropy | K-mer | Overrep | Duplication | Adapter ]
  ↓
Metrics
```

## BAM Analytics Architecture
BAM processing introduces a new `BamReader` to stream `AlignmentRecord`s. The alignment stages include:
- Alignment Statistics
- MAPQ Distribution
- Insert Size Distribution
- Coverage Statistics
- Error Rate
- Soft Clipping Statistics

### BAM Pipeline Diagram
```text
BAM
  ↓
BamReader
  ↓
BamScheduler
  ↓
[ Alignment Stats | MAPQ Dist | Insert Size | Coverage | Error Rate | Soft Clip ]
  ↓
Metrics
```

## CLI Usage
FASTQ commands:
- `qwd qc reads.fastq`
- `qwd fastq-stats reads.fastq`
- `qwd pipeline trim,filter,qc reads.fastq`

BAM commands:
- `qwd bamstats alignments.bam`
