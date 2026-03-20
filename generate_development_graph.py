import matplotlib.pyplot as plt
import numpy as np

# Development Phases and Data
phases = ["Phase Z", "Phase Y", "Phase X", "Phase W", "Phase V", "Phase U", "Phase T", "Phase 6", "Phase R"]
throughput = [5, 10, 20, 25, 30, 147, 150, 218, 1150] # Reads per second (in thousands)

# Milestone Details
milestones = [
    "Core Foundation\n(FastqParser, Arena)",
    "First Analytics\n(GC, Basic QC)",
    "Pipeline Engine\n(Filter, Trim)",
    "Advanced Stats\n(N50, Entropy)",
    "BAM Coverage\n(CIGAR, BAM Stats)",
    "SIMD & Scaling\n(Vectorized Kernels)",
    "Binding Layer\n(C ABI, Python, R)",
    "Extreme I/O\n(Block I/O, LUTs)",
    "Multicore Zero-Copy\n(mmap, Bloom, 8-Threads)"
]

plt.figure(figsize=(16, 10), dpi=140)
plt.style.use('dark_background')

# Plot Throughput Curve
x = np.arange(len(phases))
plt.plot(x, throughput, marker='o', markersize=12, linestyle='-', linewidth=4, color='#00FFCC', alpha=0.9, label="Throughput (Reads/sec)")
plt.fill_between(x, throughput, color='#00FFCC', alpha=0.1)

# Annotate Phases and Milestones with Alternating Heights to avoid overlap
for i, txt in enumerate(milestones):
    # Alternate position: higher for even, lower for odd (relative to the point)
    offset = 60 if i % 2 == 0 else -80
    color = '#00FFCC' if i == len(milestones)-1 else 'white'
    
    plt.annotate(txt, (x[i], throughput[i]), 
                 xytext=(0, offset), 
                 textcoords='offset points', ha='center', fontsize=10, 
                 color=color, fontweight='bold',
                 bbox=dict(boxstyle='round,pad=0.6', fc='#121212', ec='#00FFCC', alpha=0.8),
                 arrowprops=dict(arrowstyle='->', connectionstyle='arc3', color='#00FFCC', alpha=0.6))

# Highlight the 1M Breakthrough
plt.axhline(y=1000, color='#FF3366', linestyle='--', linewidth=2, alpha=0.6, label="Industry Gold Standard (1M/sec)")
plt.text(0, 1030, "1.0M HIGH-PERFORMANCE BARRIER", color='#FF3366', fontsize=11, fontweight='black')

# Formatting
plt.title("QwD Pipeline Development: Performance & Architecture Evolution", fontsize=22, pad=60, color='white', fontweight='bold')
plt.xlabel("Development Phase", fontsize=14, labelpad=20)
plt.ylabel("Throughput (Thousands of Reads/Second)", fontsize=14, labelpad=20)
plt.xticks(x, phases, fontsize=12)
plt.yticks(fontsize=11)
plt.grid(axis='y', linestyle='--', alpha=0.2)
plt.legend(loc='upper left', frameon=True, facecolor='#121212', edgecolor='#00FFCC', fontsize=12)

# Engineering Standards Footer
standards_text = "ENGINEERING STANDARDS: Zero-Copy mmap | SIMD Vectorization | Bounded O(1) Memory | Bit-Exact Multicore Determinism"
plt.figtext(0.5, 0.02, standards_text, ha='center', fontsize=11, color='#00FFCC', 
            bbox=dict(boxstyle='round,pad=1.0', fc='#121212', ec='#00FFCC', alpha=1.0))

# Set y-axis limit to give room for annotations
plt.ylim(-150, 1400)

plt.tight_layout(rect=[0, 0.05, 1, 0.95])
plt.savefig("QwD_Development_Proof.png")
print("Graph enhanced and generated successfully: QwD_Development_Proof.png")
