import SwiftUI

struct QualityHeatmapView: View {
    let stats: QualityDistStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Quality Distribution Heatmap", systemImage: "grid")
                    .font(.headline)
                Spacer()
                Text("Phred 0-40")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            
            if stats.data == nil || stats.data!.isEmpty {
                VStack {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No quality distribution data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
            } else {
                let safeData = stats.data!
                Canvas { context, size in
                    let columns = CGFloat(safeData.count)
                    if columns == 0 { return }
                    
                    let rows: CGFloat = 41
                    let cellWidth = size.width / columns
                    let cellHeight = size.height / rows
                    
                    // Find global max once
                    var globalMax: Int = 1
                    for col in safeData {
                        for val in col {
                            if val > globalMax { globalMax = val }
                        }
                    }
                    
                    // Use logarithmic intensity so small values are visible
                    let logMax = log10(1.0 + Double(globalMax))
                    
                    for x in 0..<safeData.count {
                        for y in 0..<41 {
                            let val = safeData[x][y]
                            if val == 0 { continue }
                            
                            // Log-scaled intensity: log(1+v) / log(1+max)
                            let intensity = log10(1.0 + Double(val)) / logMax
                            
                            // Ensure a minimum visibility for any non-zero value
                            let alpha = max(0.1, intensity)
                            
                            let rect = CGRect(
                                x: CGFloat(x) * cellWidth,
                                y: size.height - CGFloat(y + 1) * cellHeight,
                                width: cellWidth + 0.5,
                                height: cellHeight + 0.5
                            )
                            
                            // Multi-stop Color Scale: 
                            // 0-20: Red/Orange (Poor)
                            // 20-30: Yellow/Light Green (Acceptable)
                            // 30-40: Dark Green/Blue (Excellent)
                            var color = Color.red
                            if y >= 20 { color = .orange }
                            if y >= 28 { color = .yellow }
                            if y >= 33 { color = .green }
                            if y >= 37 { color = .blue }
                            
                            context.fill(Path(rect), with: .color(color.opacity(alpha)))
                        }
                    }
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
            }
            
            HStack {
                Text("Read Position (bp)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.max_pos ?? 0) bp").font(.caption.bold())
            }
        }
        .proPanel(padding: 20)
    }
}
