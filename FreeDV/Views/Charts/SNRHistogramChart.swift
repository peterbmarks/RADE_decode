import SwiftUI
import Charts

/// SNR distribution histogram (synced frames only).
struct SNRHistogramChart: View {
    let snapshots: [SignalSnapshot]
    
    private var histogramBins: [(bin: Int, count: Int)] {
        let synced = snapshots.filter { $0.syncState == 2 }
        guard !synced.isEmpty else { return [] }
        
        let grouped = Dictionary(grouping: synced) { snap in
            Int(floor(snap.snr / 2.0)) * 2
        }
        return grouped.map { (bin: $0.key, count: $0.value.count) }
            .sorted { $0.bin < $1.bin }
    }
    
    private var stats: (median: Float, mean: Float)? {
        let synced = snapshots.filter { $0.syncState == 2 }.map { $0.snr }.sorted()
        guard !synced.isEmpty else { return nil }
        let mean = synced.reduce(0, +) / Float(synced.count)
        let median = synced[synced.count / 2]
        return (median, mean)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SNR Distribution")
                .font(.system(size: 13, weight: .semibold))
            
            if histogramBins.isEmpty {
                Text("No synced data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                Chart(histogramBins, id: \.bin) { item in
                    BarMark(
                        x: .value("SNR", "\(item.bin)~\(item.bin + 2)"),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(binColor(item.bin))
                }
                .chartXAxisLabel("SNR (dB)")
                .chartYAxisLabel("Frames")
                .frame(height: 150)
                
                // Stats line
                if let s = stats {
                    HStack(spacing: 16) {
                        Text(String(format: "Mean: %.1f dB", s.mean))
                        Text(String(format: "Median: %.1f dB", s.median))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func binColor(_ bin: Int) -> Color {
        let mid = Float(bin + 1)
        if mid > 6 { return .green }
        if mid > 2 { return .yellow }
        return .red
    }
}
