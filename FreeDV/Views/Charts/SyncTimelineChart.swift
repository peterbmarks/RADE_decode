import SwiftUI
import Charts

/// Sync state color band timeline.
struct SyncTimelineChart: View {
    let snapshots: [SignalSnapshot]
    
    private var displayData: [SignalSnapshot] {
        downsample(snapshots.sorted { $0.offsetMs < $1.offsetMs }, targetPoints: 400)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sync State")
                .font(.system(size: 13, weight: .semibold))
            
            Chart(displayData, id: \.id) { snap in
                RectangleMark(
                    xStart: .value("Start", Double(snap.offsetMs) / 1000.0),
                    xEnd: .value("End", Double(snap.offsetMs + 120) / 1000.0),
                    yStart: .value("", 0),
                    yEnd: .value("", 1)
                )
                .foregroundStyle(syncColor(snap.syncState))
            }
            .chartYAxis(.hidden)
            .chartXAxisLabel("Time (s)")
            .frame(height: 30)
            
            // Legend
            HStack(spacing: 12) {
                LegendItem(color: .red, label: "Search")
                LegendItem(color: .yellow, label: "Candidate")
                LegendItem(color: .green, label: "Sync")
            }
            .font(.system(size: 10))
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func syncColor(_ state: Int) -> Color {
        switch state {
        case 2: return .green
        case 1: return .yellow
        default: return .red
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
