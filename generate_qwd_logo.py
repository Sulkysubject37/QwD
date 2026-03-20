import matplotlib.pyplot as plt
import matplotlib.patches as patches

def generate_logo():
    fig, ax = plt.subplots(figsize=(8, 8), dpi=300)
    ax.set_aspect('equal')
    ax.axis('off')

    # Colors - Technical / High-Performance Palette
    bg_color = '#FFFFFF'
    primary_color = '#1A1A1B'  # Deep Slate
    accent_color = '#007AFF'   # Electric Blue (Apple-style)
    grid_color = '#E5E5E7'     # Light Gray

    # 1. Background Grid (The Bit-Matrix / Columnar Foundation)
    grid_size = 12
    for x in range(grid_size):
        for y in range(grid_size):
            circle = patches.Circle((x, y), 0.05, color=grid_color, alpha=0.5)
            ax.add_patch(circle)

    # 2. The Stylized 'Q' (Built from Vertical SIMD Lanes)
    # The circular part of the Q as three vertical "lanes"
    # Lane 1 (Left)
    ax.add_patch(patches.Rectangle((3.5, 4), 0.8, 4, color=primary_color, lw=0, capstyle='round'))
    # Lane 2 (Middle Top)
    ax.add_patch(patches.Rectangle((5.5, 7.2), 0.8, 0.8, color=primary_color, lw=0))
    # Lane 3 (Right)
    ax.add_patch(patches.Rectangle((7.5, 4), 0.8, 4, color=primary_color, lw=0))
    # Lane 4 (Bottom Connector)
    ax.add_patch(patches.Rectangle((4.3, 3.2), 3.2, 0.8, color=primary_color, lw=0))
    # Top Connector
    ax.add_patch(patches.Rectangle((4.3, 8), 3.2, 0.8, color=primary_color, lw=0))

    # The 'Q' Tail (The Deterministic Exit / SIMD Lane)
    # Designed as a diagonal 45-degree vector
    tail_points = [[7.5, 4], [9.5, 2], [10.2, 2.7], [8.2, 4.7]]
    tail = patches.Polygon(tail_points, color=accent_color, lw=0)
    ax.add_patch(tail)

    # 3. The "Phase Q" 4x4 Bitplane Indicator
    # Representing A, C, G, T planes
    for i in range(2):
        for j in range(2):
            dot = patches.Circle((5.4 + i*1.0, 5.1 + j*1.0), 0.15, color=accent_color)
            ax.add_patch(dot)

    # 4. Typography
    plt.text(5.9, 1.0, 'QwD', fontsize=42, fontweight='bold', 
             family='sans-serif', color=primary_color, ha='center', va='center')
    
    plt.text(5.9, 0.2, 'QUALITY WITH DETERMINISM', fontsize=10, 
             family='sans-serif', color=primary_color, alpha=0.6, ha='center', va='center')

    # Setting limits to center the content
    ax.set_xlim(-1, 13)
    ax.set_ylim(-1, 11)

    # Save
    plt.savefig('qwd_logo.png', bbox_inches='tight', pad_inches=0.5, transparent=False, facecolor=bg_color)
    print("Logo generated successfully: qwd_logo.png")

if __name__ == "__main__":
    generate_logo()
