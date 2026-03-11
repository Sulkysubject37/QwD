# Phase Z: Repository Initialization and Core Engine

## Repository Initialization
The project was initialized with the following structure:
- `core/`: Engine modules (parser, scheduler, allocator)
- `stages/`: Analytics and processing stages
- `io/`: FASTQ/BAM readers
- `bindings/`: Python and R support
- `apps//cli`: Main entry point
- `scripts/`: Toolchain and data generation scripts

## Core Engine Modules
1. **Parser**: A streaming FASTQ reader that produces `Read` objects with zero-copy slices.
2. **Scheduler**: Manages read distribution to various processing stages.
3. **Allocator**: A wrapper around Zig allocators (primarily Arena) to ensure bounded, predictable memory usage.
4. **Parallel Scheduler**: (Added in Phase U) Enables deterministic multithreaded processing.
5. **SIMD Operations**: (Added in Phase U) Hardware-accelerated inner loops for maximum throughput.

## Architecture
```text
FASTQ → Parser → Scheduler → Metrics
```
The parser reads 4-line FASTQ records into a reusable buffer. The scheduler then forwards these records to registered stages. The engine has since evolved to support hardware-accelerated processing and multi-core scalability.
