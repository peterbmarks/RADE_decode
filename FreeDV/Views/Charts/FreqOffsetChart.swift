import SwiftUI
import Charts

/// Frequency offset over time (only SYNC periods).
struct FreqOffsetChart: View {
    let snapshots: [SignalSnapshot]
    
    private var syncedData: [SignalSnapshot] {
        let synced = snapshots.filter { $0.syncState == 2 }.sorted { $0.offsetMs < $1.offsetMs }
        return downsample(synced, targetPoints: 400)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frequency Offset")
                .font(.system(size: 13, weight: .semibold))
            
            if syncedData.isEmpty {
                Text("No synced data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                Chart(syncedData, id: \.id) { snap in
                    LineMark(
                        x: .value("Time", Double(snap.offsetMs) / 1000.0),
                        y: .value("Hz", snap.freqOffset)
                    )
                    .foregroundStyle(.cyan)
                    .interpolationMethod(.monotone)
                }
                .chartYAxisLabel("Hz")
                .chartXAxisLabel("Time (s)")
                .frame(height: 120)
                
                // Stats
                let offsets = syncedData.map { $0.freqOffset }
                let avg = offsets.reduce(0, +) / Float(max(offsets.count, 1))
                Text(String(format: "Mean: %.1f Hz", avg))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
