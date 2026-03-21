# QwD Language Bindings

This directory contains the official language bindings for the QwD bioinformatics streaming engine.

## Python Bindings (`bindings/python`)

The Python bindings provide a high-level wrapper around the QwD shared library using `ctypes`.

### Installation
```bash
pip install ./bindings/python
```

### Usage
```python
import qwd

# Perform QC on a FASTQ file
results = qwd.qc("path/to/reads.fastq")

# Access basic statistics
print(results['basic_stats']['total_reads'])
```

## R Bindings (`bindings/r`)

The R bindings are provided as a standard R package.

### Installation
```R
# From the project root
install.packages("bindings/r", repos = NULL, type = "source")
```

### Usage
```R
library(qwd)

# Perform QC
metrics <- qwd_qc("path/to/reads.fastq")

# Plot results (if plotting stages are integrated)
print(metrics$basic_stats$total_reads)
```

## Building the Shared Library
The bindings depend on the `qwd` shared library. Build it first using:
```bash
zig build -Doptimize=ReleaseFast
```
The build system automatically places the `.so` / `.dylib` / `.dll` in the correct location for the bindings to find them.
