#ifndef QWD_H
#define QWD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define QWD_VERSION_MAJOR 1
#define QWD_VERSION_MINOR 3
#define QWD_VERSION_PATCH 0
#define QWD_VERSION_STR "1.3.0"

typedef struct qwd_context_t qwd_context_t;

typedef struct {
    uint32_t thread_count;
    uint32_t use_exact_mode;
    uint32_t trim_front;
    uint32_t trim_tail;
    float min_quality;
    uint32_t _pad1;

    uint64_t memory_bytes;
    float cpu_percent;
    uint32_t _pad2;

    uint64_t read_count;
    uint64_t total_bases;
    uint64_t gc_count;
    uint64_t at_count;
    uint64_t n_count;
    uint64_t violations;

    uint32_t status; 
    uint32_t cancelled; // New: Cancellation Signal
    uint64_t gc_distribution[101];
    uint64_t length_distribution[1000];
    uint64_t quality_heatmap[150 * 42];
} qwd_telemetry_t;

qwd_context_t* qwd_create(void);
void qwd_destroy(qwd_context_t* ctx);
void qwd_execute_file(qwd_context_t* ctx, const char* path);
void qwd_reset_state(qwd_context_t* ctx);
void qwd_set_params(qwd_context_t* ctx, uint32_t threads, uint32_t exact, uint32_t trim_f, uint32_t trim_t, float min_q);
void qwd_get_telemetry(qwd_context_t* ctx, qwd_telemetry_t* out);
void qwd_set_telemetry_hook(qwd_context_t* ctx, void* hook);
void qwd_init_state(qwd_context_t* ctx);
void qwd_execute_analysis(qwd_context_t* ctx, const char* path);

const char* qwd_platform_open_file_picker(void);

#ifdef __cplusplus
}
#endif

#endif
