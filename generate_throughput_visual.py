import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import matplotlib.ticker as ticker

# --- PROFESSIONAL DESIGN SYSTEM ---
plt.rcParams.update({
    'font.size': 12,
    'axes.facecolor': '#FDFEFE',
    'figure.facecolor': '#FFFFFF',
    'axes.edgecolor': '#2C3E50',
    'grid.color': '#D5DBDB',
    'font.family': 'sans-serif',
    'font.sans-serif': ['Arial']
})

# Load data
df = pd.read_csv('validation_results.csv')

# Explicit Mapping
engine_map = {
    'auto': 'Plain FASTQ (Baseline)',
    'qwd': 'QwD Native (Zig)',
    'libdeflate': 'libdeflate (SIMD C)'
}
# We only want to compare these three for clarity
df = df[df['engine'].isin(['auto', 'qwd', 'libdeflate'])].copy()
df['Engine'] = df['engine'].map(engine_map)
df['Format'] = df['format'].map({'plain': 'Plain', 'gz': 'Standard GZ', 'bgzf': 'BGZF'})
df['Mode'] = df['mode'].str.upper()

# Hard-coded Palette for ZERO ambiguity
colors = {
    'Plain FASTQ (Baseline)': '#2C3E50', # Navy
    'QwD Native (Zig)': '#27AE60',       # Green
    'libdeflate (SIMD C)': '#E74C3C'     # Red
}

# Create Figure
g = sns.catplot(
    data=df,
    kind="bar",
    x="threads",
    y="reads_sec",
    hue="Engine",
    hue_order=['Plain FASTQ (Baseline)', 'QwD Native (Zig)', 'libdeflate (SIMD C)'],
    col="Format",
    row="Mode",
    palette=colors,
    height=5,
    aspect=1.2,
    edgecolor="white",
    linewidth=1,
    legend=False
)

# --- READABILITY REFINEMENT ---
def format_val(x):
    if x >= 1e6: return f'{x/1e6:.1f}M'
    if x >= 1e3: return f'{int(x/1e3)}k'
    return f'{int(x)}'

for ax in g.axes.flat:
    ax.set_yscale('log')
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, pos: format_val(x)))
    ax.set_ylim(1e5, 1e7) # Focus on the relevant magnitude
    
    # Add clear text labels on top of bars
    for container in ax.containers:
        try:
            ax.bar_label(container, fmt=lambda x: format_val(x), padding=3, fontsize=8, fontweight='bold')
        except:
            pass

g.set_axis_labels("Threads", "Throughput (Reads/Sec)")
g.set_titles("{row_name} | {col_name}", weight='bold', size=14)

# Dedicated Legend Space (Right Side, No Overlap)
plt.subplots_adjust(top=0.85, right=0.82, bottom=0.15)
g.fig.suptitle('QwD Phase P.2 Performance & Stability Matrix', fontsize=24, fontweight='bold', y=0.96)

# Explicit Color Description Box
color_desc = (
    "COLOR KEY & ENGINE ROLES:\n"
    "■ NAVY: Plain FASTQ Baseline (System Peak)\n"
    "■ GREEN: QwD Native (Pure Zig Implementation)\n"
    "■ RED: libdeflate (SIMD-Accelerated C Backend)"
)
plt.figtext(0.83, 0.5, color_desc, fontsize=12, fontweight='bold', color='#2C3E50',
            bbox=dict(facecolor='white', alpha=0.9, edgecolor='#BDC3C7', boxstyle='round,pad=1'))

# Place standard legend on the right
handles, labels = g.axes[0][0].get_legend_handles_labels()
leg = g.fig.legend(handles, labels, loc='upper right', bbox_to_anchor=(0.98, 0.85), title='Engine Class')
leg.get_title().set_fontweight('bold')

plt.savefig('QwD_Phase_P_Final_Report.png', dpi=300, bbox_inches='tight')
print("SUCCESS: QwD_Phase_P_Final_Report.png generated.")
