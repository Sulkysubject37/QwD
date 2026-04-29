#include <stdio.h>
#include <stddef.h>
#include "../bindings/c/qwd.h"

int main() {
    printf("--- C TELEMETRY ABI REPORT ---\n");
    printf("Total Size: %zu bytes\n", sizeof(qwd_telemetry_t));
    
    printf("\nFIELD OFFSETS:\n");
    printf("read_count:   %zu\n", offsetof(qwd_telemetry_t, read_count));
    printf("total_bases:  %zu\n", offsetof(qwd_telemetry_t, total_bases));
    printf("status:       %zu\n", offsetof(qwd_telemetry_t, status));
    printf("gc_dist:      %zu\n", offsetof(qwd_telemetry_t, gc_distribution));
    printf("len_dist:     %zu\n", offsetof(qwd_telemetry_t, length_distribution));
    printf("heatmap:      %zu\n", offsetof(qwd_telemetry_t, quality_heatmap));
    
    return 0;
}
