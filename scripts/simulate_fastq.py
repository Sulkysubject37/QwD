import random
import sys

def generate_realistic_fastq(filename, num_reads):
    adapters = ["AGCTATCG", "GATCGATC", "AAAAAA"]
    print(f"Generating {num_reads} reads into {filename}...")
    with open(filename, 'w') as f:
        for i in range(num_reads):
            read_id = f"@READ_{i}"
            length = random.randint(75, 150)
            if random.random() < 0.01:
                seq = random.choice("ACGT") * length
            else:
                seq = "".join(random.choices("ACGT", k=length))
            if random.random() < 0.02:
                adapter = random.choice(adapters)
                if len(seq) > len(adapter):
                    seq = seq[:-len(adapter)] + adapter
            quals = []
            for pos in range(length):
                decay = int(pos / 10)
                score = max(0, 33 - decay + random.randint(-5, 5))
                quals.append(chr(score + 33))
            qual_str = "".join(quals)
            f.write(read_id + "\n")
            f.write(seq + "\n")
            f.write("+\n")
            f.write(qual_str + "\n")
    print("Done.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 simulate_fastq.py <filename> <num_reads>")
        sys.exit(1)
    filename = sys.argv[1]
    num_reads = int(sys.argv[2])
    generate_realistic_fastq(filename, num_reads)
