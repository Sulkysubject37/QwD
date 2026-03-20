# QwD Stress Test Report

Date: Fri Mar 20 19:29:22 IST 2026
Machine: Darwin MDs-MacBook-Air-3.local 25.3.0 Darwin Kernel Version 25.3.0: Wed Jan 28 20:53:31 PST 2026; root:xnu-12377.91.3~2/RELEASE_ARM64_T8103 arm64

| Dataset | Threads | Memory Cap | Time (s) | Throughput (reads/s) | Peak RSS (MB) | Status |
|---------|---------|------------|----------|----------------------|---------------|--------|
| test_1M.fastq | 1 | 256MB | 3s | 333333 | 50 | ✅ PASS |
| test_1M.fastq | 4 | 256MB | 3s | 333333 | 193 | ✅ PASS |
| test_1M.fastq | 8 | 256MB | 3s | 333333 | 139 | ✅ PASS |
| test_1M.fastq | 4 | 128MB | 3s | 333333 | 77 | ✅ PASS |
| test_1M.fastq | 4 | 64MB | 4s | 250000 | 32 | ✅ PASS |
| stress_10M.fastq | 1 | 512MB | 33s | 303030 | 54 | ✅ PASS |
| stress_10M.fastq | 4 | 512MB | 33s | 303030 | 340 | ✅ PASS |
| stress_10M.fastq | 8 | 512MB | 33s | 303030 | 333 | ✅ PASS |
| stress_10M.fastq | 4 | 256MB | 36s | 277777 | 202 | ✅ PASS |
