#pragma once
const char* qwd_fastq_qc(const char* path);
const char* qwd_fastq_qc_fast(const char* path, int threads);
const char* qwd_bam_stats(const char* path);
const char* qwd_pipeline(const char* config_path, const char* input_path);
void qwd_free_string(const char* ptr);
