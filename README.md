# QwD (قَلَّ وَدَلَّ): The Genomic Command Center
![Version](https://img.shields.io/badge/Version-1.3.0--Raja--Reform-blueviolet?style=flat-square)
![Build](https://github.com/Sulkysubject37/qwd/actions/workflows/native_performance.yml/badge.svg)
![License](https://img.shields.io/badge/License-AFL--3.0-green?style=flat-square)

**QwD (Raja Reform)** is a high-performance, platform-agnostic genomic engine designed for the ultra-fast analysis of FASTQ and BGZF data. Built with Zig 0.16.0-dev and C++17, it utilizes bitplane-columnar storage and register-based SIMD transposition to achieve sub-second latencies on standard hardware.

## 🚀 The Raja Reform (v1.3.0)
The "Raja Reform" milestone marks the transition to a **Pure Agnostic Core**. By decoupling the computational engine from platform-specific I/O and scheduling, QwD now runs with bit-exact consistency across Desktop and Mobile.

### Key Pillars:
- **Agnostic Core**: Zero dependencies on `std.Thread` or `std.posix` in the computational kernels.
- **SIMD Power**: 16x16 register-based transposition (ARM NEON / x86 AVX2).
- **Parallel Scheduler**: Dual-pool worker model for asynchronous decompression and analysis.
- **Unified C-ABI**: A hardened binary interface for high-level integration (Swift, Android/Sokol).
- **Native-First Strategy**: Optimized for raw hardware performance on Linux, macOS, and Android.

## 📊 Analytical Suite
The engine provides a comprehensive set of QC metrics:
- **Basic Stats**: Total reads, bases, and length distributions.
- **GC Content**: High-resolution histogram bins (0-100%).
- **N-Statistics**: Precise non-ACGT base tracking.
- **Length Distribution**: Binned length mapping.
- **Quality Distribution**: Position-wise PHRED score mappings.
- **Nucleotide Composition**: Granular A/C/G/T/N counts.

## 🛠 Project Structure
- **`core/`**: The Agnostic Engine (Bitplanes, Pipeline, Parsers).
- **`bindings/c/`**: Hardened C-ABI bridge for universal integration.
- **`apps/cli/`**: High-throughput terminal analyzer.
- **`apps/dashboard/`**: The Sokol-based Native Workstation (Cross-platform GUI).
- **`stages/`**: Modular analytical units.

## 🔨 Build & Run
QwD uses a unified Zig build system.

### Build CLI:
```bash
zig build
./zig-out/bin/qwd input.fastq
```

### Build & Run Workstation:
```bash
zig build run-workstation
```

## 📱 Future: Android Native
Phase 1.3.x focuses on the **Android Native APK**. Using a unified Sokol + Zig stack, the Genomic Command Center provides laboratory-grade analysis directly on mobile devices without JNI overhead.

---
**Author:** MD. Arshad, Dept. of Computer Science, Jamia Millia Islamia.
**License:** Academic Free License ("AFL") v. 3.0
