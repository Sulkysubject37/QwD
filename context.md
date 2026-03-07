# QwD Project Context

Project: QwD (qalla wa dalla)
Meaning: brevity with clarity

Tagline:
QwD — minimal passes, maximal insight.

Purpose:
QwD is a streaming analytics engine for sequencing data (FASTQ/BAM) designed to provide real-time diagnostics while minimizing I/O passes and memory overhead.

---

# Core Philosophy

QwD follows the principle of **qalla wa dalla**:
deliver meaningful insights using minimal computation passes and clear system architecture.

---

# Design Principles

1. Single-pass computation
   - All analytics should operate in a single streaming pass when possible.

2. Streaming-first architecture
   - No module should require full dataset materialization.

3. Deterministic memory usage
   - Memory consumption must remain bounded regardless of dataset size.

4. Modular stage design
   - Each analytic operation must be implemented as a composable stage.

5. Zero-copy data flow
   - FASTQ/BAM records should avoid unnecessary copying.

6. Concurrent execution
   - Stages should run concurrently where safe.

7. Language-agnostic interfaces
   - Core engine is written in Zig.
   - External bindings: CLI, Python, R, API.

8. Real-time analytics
   - Metrics must be computed incrementally.

---

# Architectural Model

Pipeline abstraction:

Input → Parser → Stages → Aggregator → Output

Example:

FASTQ stream
    ↓
parser
    ↓
[quality_stats | gc_analysis | read_length]
    ↓
metrics output

---

# Core Modules

core/
- parser
- scheduler
- allocator

stages/
- qc
- gc
- read_length
- kmer
- adapter

io/
- fastq
- bam

bindings/
- python
- r

apps/
- cli
- dashboard

---

# Implementation Language

Core language: Zig

Reasons:
- deterministic memory control
- strong C ABI compatibility
- simple build system
- cross-compilation

---

# Coding Policies

1. Avoid unnecessary allocations.
2. Prefer streaming algorithms.
3. No global mutable state.
4. All stages must support incremental processing.
5. Benchmark critical paths.
6. Write deterministic tests.

---

# Performance Goals

Target metrics:

- >1M reads/sec processing
- constant memory usage
- minimal allocation overhead

---

# Non-goals

QwD will NOT implement:

- genome alignment
- variant calling
- assembly

It focuses on **streaming analytics and preprocessing**.

---

# Motto Reminder

Minimal passes.
Maximal insight.
