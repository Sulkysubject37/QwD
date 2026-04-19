#pragma once
const char* qwd_fastq_qc(const char* path);
const char* qwd_fastq_qc_ex(const char* path, int threads, int mode, int gzip_mode);
const char* qwd_bam_stats(const char* path, int threads);
const char* qwd_pipeline(const char* config_json, const char* input_path);
void qwd_free_string(const char* ptr);
