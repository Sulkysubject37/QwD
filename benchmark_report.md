# Native Zig QwD Benchmark Report

Date: Fri Mar 20 16:03:32 IST 2026

## stress_1M.fastq (1 Million Reads)
### stress_1M.fastq — Threads: 1, Max-Memory: 256MB
```
        3.47 real         3.32 user         0.06 sys
            57131008  maximum resident set size
                   0  average shared memory size
                   0  average unshared data size
                   0  average unshared stack size
                3985  page reclaims
                  15  page faults
                   0  swaps
                   0  block input operations
                   0  block output operations
                   0  messages sent
                   0  messages received
                   0  signals received
                   2  voluntary context switches
                3810  involuntary context switches
         10588413035  instructions retired
         10388215338  cycles elapsed
            56624000  peak memory footprint
```

### stress_1M.fastq — Threads: 4, Max-Memory: 256MB
```
time: command terminated abnormally
       83.93 real        90.37 user       281.40 sys
           141033472  maximum resident set size
                   0  average shared memory size
                   0  average unshared data size
                   0  average unshared stack size
                8770  page reclaims
                   3  page faults
                   0  swaps
                   0  block input operations
                   0  block output operations
                   0  messages sent
                   0  messages received
                   0  signals received
                   4  voluntary context switches
             6139180  involuntary context switches
       1843203329208  instructions retired
       1013780943736  cycles elapsed
           140625216  peak memory footprint
time: signal: Invalid argument
```

### stress_1M.fastq — Threads: 8, Max-Memory: 256MB
```
time: command terminated abnormally
       11.43 real         7.03 user        66.44 sys
           146194432  maximum resident set size
                   0  average shared memory size
                   0  average unshared data size
                   0  average unshared stack size
                9067  page reclaims
                  16  page faults
                   0  swaps
                   0  block input operations
                   0  block output operations
                   0  messages sent
                   0  messages received
                   0  signals received
                   7  voluntary context switches
             6814813  involuntary context switches
        180975757330  instructions retired
        189147929798  cycles elapsed
           145819072  peak memory footprint
time: signal: Invalid argument
```

### stress_1M.fastq — Threads: 16, Max-Memory: 256MB
```
