import SwiftUI
import Charts

struct KmerBin: Identifiable {
    let id: Int
    let count: Int
}

struct KmerSpectrumView: View {
    let stats: KmerSpectrumStats
    
    var body: some View {
        let bins = stats.counts.enumerated().map { KmerBin(id: $0.offset, count: $0.element) }
        let hasData = stats.counts.contains { $0 > 0 }
        
        VStack(alignment: .leading, spacing: 12) {
            Label("\(stats.k)-mer Frequency Spectrum", systemImage: "waveform.path")
                .font(.headline)
            
            if !hasData {
                VStack {
                    Image(systemName: "waveform.path.ecg")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No k-mer frequency data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            } else {
                Chart(bins) { bin in
                    if bin.count > 0 {
                        AreaMark(
                            x: .value("Hash", bin.id),
                            y: .value("Count", bin.count)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.3))
                        
                        LineMark(
                            x: .value("Hash", bin.id),
                            y: .value("Count", bin.count)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(height: 180)
                // Removed .log scale to prevent trace trap crashes on zero/near-zero values
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
            
            Text("Distribution of \(stats.counts.count) possible \(stats.k)-mers. Linear scale.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .proPanel(padding: 20)
    }
}
