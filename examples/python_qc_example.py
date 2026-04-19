import sys
import os
import time

# Add bindings/python to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../bindings/python')))

import qwd
import json

def main():
    if len(sys.argv) < 2:
        print("Usage: python python_qc_example.py <file>")
        return

    fastq_path = sys.argv[1]
    print(f"QwD Python Binding Example - Analyzing {fastq_path}")
    
    start_time = time.time()
    
    # Run QC
    print("Running QC...")
    try:
        metrics = qwd.qc(fastq_path, threads=4)
        end_time = time.time()
        
        duration = end_time - start_time
        print(f"QC Completed in {duration:.4f}s")
        print(f"Read Count: {metrics.get('read_count', 'N/A')}")
        
    except Exception as e:
        print(f"Error during QC: {e}")

if __name__ == "__main__":
    main()
