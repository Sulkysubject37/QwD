import os
import gzip
import random

def generate_fastq(path, count=100000, read_len=16):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    random.seed(42)
    with open(path, 'w') as f:
        for i in range(count):
            seq = "".join(random.choices("ACGT", k=read_len))
            qual = "I" * read_len
            f.write(f"@R_{i}\n{seq}\n+\n{qual}\n")

def generate_bam(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        # Minimal BAM magic + dummy header
        f.write(b"BAM\x01")
        f.write((10).to_bytes(4, 'little')) # Header text len
        f.write(b"QwD Dummy\n")
        f.write((0).to_bytes(4, 'little'))  # Num refs

if __name__ == "__main__":
    base_dir = "tests/fixtures"
    fastq_path = os.path.join(base_dir, "sample.fastq")
    gz_path = fastq_path + ".gz"
    bam_path = os.path.join(base_dir, "sample.bam")

    print(f"Generating {fastq_path}...")
    generate_fastq(fastq_path)

    print(f"Compressing to {gz_path}...")
    with open(fastq_path, 'rb') as f_in:
        with gzip.open(gz_path, 'wb') as f_out:
            f_out.writelines(f_in)

    print(f"Generating {bam_path}...")
    generate_bam(bam_path)
    print("Test data generation complete.")
