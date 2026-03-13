import random
import sys

def generate_realistic_fastq(filename, num_reads):
    adapters = ["AGCTATCG", "GATCGATC", "AAAAAA"]
    with open(filename, 'w') as f:
        for i in range(num_reads):
            read_id = f"@READ_{i}"
            length = random.randint(100, 150)
            seq = "".join(random.choices("ACGT", k=length))
            quals = "".join([chr(random.randint(30, 40) + 33) for _ in range(length)])
            f.write(read_id + "\n")
            f.write(seq + "\n")
            f.write("+\n")
            f.write(quals + "\n")

if __name__ == "__main__":
    num = 1000000
    if len(sys.argv) > 1:
        num = int(sys.argv[1])
    generate_realistic_fastq("stress_data.fastq", num)
    print(f"Generated {num} reads.")
