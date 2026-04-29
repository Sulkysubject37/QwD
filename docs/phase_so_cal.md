# Phase So-Cal: The Unified Machine-Code Architecture

## Overview
Phase So-Cal transitions the QwD genomic engine from a CLI/JNI-fragmented toolset into a single, unified, high-performance Graphical Application. By leveraging the Zig compiler, the Sokol graphics layer, and the Dear ImGui (dcimgui) docking branch, QwD becomes a "Genomic Command Center" that runs as pure machine code across all major platforms.

## Core Directives
- **Zero JNI/Java:** Elimination of the Android/Swift UI wrappers. 100% of the UI and core logic reside in the same memory space.
- **Docking Architecture:** Professional, multi-panel workstation aesthetic (draggable charts, telemetry logs, data ingestion bins).
- **Ubiquitous Deployment:** A single codebase must compile to Native Desktop (macOS/Windows/Linux), WebAssembly (WASM), and Mobile (APK).
- **Aesthetic:** Modern, highly appealing to both deep-technical bioinformaticians and non-technical researchers. High-density data visualization.

---

## Sub-Phases & Execution Protocol

### Sub-Phase 1: The Graphic Skeleton (Foundation)
- **Objective:** Establish the Sokol/dcimgui build pipeline within `build.zig`.
- **Key Tasks:**
  - [x] Purge legacy Java/Kotlin boilerplate (`apps/android`).
  - [x] Import `sokol-zig` via the Zig package manager.
  - [x] Import `cimgui` (C-bindings for ImGui).
  - [ ] Configure the build system to compile C-Imgui and link it to Sokol.
  - [ ] Initialize the Metal/GL graphics context and render the first blank ImGui frame.
- **Status:** IN PROGRESS

### Sub-Phase 2: The Command Center UI (Design & Layout)
- **Objective:** Construct the professional genomic interface.
- **Key Tasks:**
  - Implement the **Ingestion Zone:** File selection for FASTQ/BAM inputs.
  - Implement the **Telemetry Board:** Real-time logging of QwD native execution (reads/sec, memory usage).
  - Implement the **Visual Analytics Engine:** Map QwD's output bins (GC Distribution, Length Distribution, Quality Decay) into high-quality ImGui plotting widgets (`ImPlot` integration if necessary, or custom ImGui primitives).
- **Status:** PENDING

### Sub-Phase 3: The Native Validation (macOS/Desktop)
- **Objective:** Verify the UI and Core integration on the host system.
- **Key Tasks:**
  - Bind the UI "Execute" button to the `core/pipeline` synchronously or asynchronously.
  - Validate the 350MB memory cap is respected when the UI and Engine share the same allocator.
  - Ensure 120Hz UI responsiveness during heavy SIMD data processing.
- **Status:** PENDING

### Sub-Phase 4: The WebAssembly Singularity (WASM)
- **Objective:** Compile the exact same application to run in any web browser.
- **Key Tasks:**
  - Add the `wasm32-emscripten` or `wasm32-freestanding` target to `build.zig`.
  - Handle virtual file systems (allowing the user to "upload" a FASTQ file into the browser memory for the QwD engine to process).
  - *Note on Hardware Support:* WASM abstracts the hardware. It runs on any device with a modern browser (iOS, Android, Windows, Mac). SIMD instructions in WASM (Wasm SIMD128) must be mapped or gracefully degraded from the native ARM64 NEON kernels.
- **Status:** PENDING

### Sub-Phase 5: The Mobile Re-Conquest (Android APK)
- **Objective:** Package the pure-machine-code app for Android devices.
- **Key Tasks:**
  - Utilize `sokol-app`'s native Android backend (`NativeActivity`).
  - Configure the APK packaging step (handling the `AndroidManifest.xml` and keystore) without requiring the user to write Java.
  - Verify touch-input mapping to the ImGui UI.
- **Status:** PENDING

---

## Technical Audit Log
*(This section will be updated by the specialized agents upon the completion of each sub-phase to guarantee transparency and technical rigor.)*
