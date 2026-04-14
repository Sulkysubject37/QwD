import SwiftUI
import Charts

struct TaxonomyProfileView: View {
    let taxa: [TaxonMatch]
    
    var body: some View {
        let hasData = taxa.contains { $0.count > 0 }
        
        VStack(alignment: .leading, spacing: 16) {
            Label("Taxonomic Composition", systemImage: "leaf.arrow.triangle.circlepath")
                .font(.headline)
            
            if !hasData {
                Text("No taxonomic matches detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(taxa) { item in
                    BarMark(
                        x: .value("Reads", item.count),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Taxon", item.taxon))
                }
                .frame(height: 40)
                .chartLegend(.hidden)
            }
            
            VStack(spacing: 8) {
                ForEach(taxa.sorted(by: { $0.count > $1.count })) { item in
                    if item.count > 0 {
                        HStack {
                            Circle()
                                .fill(taxonColor(item.taxon))
                                .frame(width: 8, height: 8)
                            Text(item.taxon)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.count.formatted())")
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .proPanel(padding: 20)
    }
    
    private func taxonColor(_ name: String) -> Color {
        switch name {
        case "Homo sapiens":      return .blue
        case "Escherichia coli":  return .orange
        case "Mycoplasma":        return .purple
        case "PhiX Control":      return .green
        case "Sequencing Adapter": return .red
        default:                  return .gray
        }
    }
}
