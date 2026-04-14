# Phase Tax-ed: Taxonomic Screening & High-Definition Analytics

## Overview
Phase Tax-ed ("Taxonomy-Screened") evolves QwD from a quality assessment tool into a high-fidelity diagnostic instrument. This phase introduces real-time taxonomic contamination detection and expands the visual analytics stack with professional-grade, high-density scientific visualizations.

## Core Engine: Diagnostic Sensors (Zig)

### 1. SIMD Taxonomic Profiler (`TaxedStage`)
The `TaxedStage` implements a "Mini-Kraken" engine designed for sub-second contamination screening.
- **Algorithm:** Uses a 16-mer voting system against a compact signature database.
- **Database:** Curated set of high-leverage 16-mers for common contaminants:
    - *Homo sapiens* (Host DNA leakage)
    - *Escherichia coli* (Laboratory contamination)
    - *Mycoplasma* (Cell culture contamination)
    - *PhiX Control* (Illumina internal standards)
    - *Sequencing Adapters* (Residual library prep artifacts)
- **Performance:** Leveraging the **Bitplane Core**, the profiler scans millions of reads per second with $<10\%$ total pipeline overhead.

### 2. HD Quality Distribution (`QualityDistStage`)
Replaces aggregate mean-quality metrics with a full 2D probability density matrix.
- **Data Model:** Tracks a `[Position][PhredScore]` matrix (1024 x 41 bins).
- **SIMD Optimization:** Implements a vectorized popcount accumulator that processes 32 read positions simultaneously, ensuring data density does not degrade engine throughput.
- **Memory Safety:** Uses heap-allocated telemetry buffers to prevent stack overflow on large-scale parallel runs.

---

## High-Definition Dashboard (SwiftUI)

Phase Tax-ed introduces three primary visualization engines to the macOS Dashboard:

### 1. Quality Heatmap (`QualityHeatmapView`)
A logarithmic-scaled heatmap rendering the full distribution of Phred scores across read positions.
- **Engine:** High-performance `Canvas` rendering.
- **Color Scale:** Multi-stop scientific gradient (Red -> Yellow -> Green -> Blue) representing poor to excellent quality zones.
- **Visibility:** Logarithmic normalization ensures that low-frequency "quality shocks" are visible to the researcher.

### 2. K-mer Frequency Spectrum (`KmerSpectrumView`)
Visualizes the library complexity by plotting the occurrence frequency of all possible k-mers.
- **Representation:** Linear `AreaMark` chart showing the genomic "fingerprint."
- **Utility:** Instant identification of overrepresented sequences, adapter contamination, and low-complexity library preparation issues.

### 3. Taxonomic Composition (`TaxonomyProfileView`)
A specialized compositional view of the sample's biological origin.
- **Visuals:** Stacked normalized bar charts with a categorized taxonomic legend.
- **Actionable Data:** Explicit read counts for host vs. contaminant hits, allowing for immediate "Go/No-Go" decisions in clinical or field environments.

---

## Engineering & Hardening
- **Segfault Resolution:** Transitioned all large-scale analytical stages to heap-based memory management.
- **Performance Restoration:** Refactored analytical loops to leverage SIMD vectorization, resolving bottlenecks that previously caused 200% CPU spikes.
- **JSON Stability:** Unified the reporting schema across the Zig core and Swift models, adding safety guards against division-by-zero and logarithmic domain errors.
