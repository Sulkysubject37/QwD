import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

df = pd.read_csv('definitive_bench.csv')
# Exclude the failed StandardGZ compat run
df = df[df['time_sec'] > 0.1]

df['Throughput'] = 1000000 / df['time_sec']
df['Label'] = df['format'] + " (" + df['decomp'] + ")"

sns.set_theme(style="whitegrid")
plt.figure(figsize=(12, 7))
ax = sns.barplot(data=df, x='Label', y='Throughput', hue='analysis', palette='viridis')

plt.title('QwD Final Performance Report: Integrated GZIP Engine', fontsize=16, fontweight='bold')
plt.ylabel('Throughput (Reads / Second)', fontsize=12)
plt.xlabel('Execution Path', fontsize=12)

# Add watermark
plt.text(0.5, 0.5, 'qwd', transform=ax.transAxes, fontsize=100, color='gray', alpha=0.1, ha='center', va='center', rotation=30)

plt.savefig('qwd_definitive_benchmark.png', dpi=300)
print("Graph saved: qwd_definitive_benchmark.png")

print("\n--- Final Reads/Sec Report ---")
for _, row in df.iterrows():
    print(f"{row['Label']:<30} | {row['analysis']:<8} | {int(row['Throughput']):>10} reads/sec")
