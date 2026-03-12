import qwd
import json

# QwD Python Example
# Demonstrates FASTQ QC and BAM analytics.

def main():
    print("QwD Python Binding Example")
    
    # Run QC
    print("
Running QC on sample data...")
    # Using a dummy call since ABI is currently a stub for demonstration
    metrics = qwd.qc("data/sample.fastq")
    print(f"Status: {metrics['status']}")
    print(f"File:   {metrics['file']}")

    # Run BAM stats
    print("
Running BAM stats...")
    bam_stats = qwd.bamstats("data/sample.bam")
    print(f"BAM Status: {bam_stats['status']}")

if __name__ == "__main__":
    main()
