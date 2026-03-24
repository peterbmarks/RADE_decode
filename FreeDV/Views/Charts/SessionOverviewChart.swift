import SwiftUI
import Charts
import SwiftData

/// Cross-session trend chart showing average SNR over time.
struct SessionOverviewChart: View {
    let sessions: [ReceptionSession]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Trends")
                .font(.system(size: 13, weight: .semibold))
            
            if sessions.isEmpty {
                Text("No sessions recorded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
            } else {
                Chart(sessions) { session in
                    PointMark(
                        x: .value("Date", session.startTime),
                        y: .value("Avg SNR", session.avgSNR)
                    )
                    .symbolSize(CGFloat(max(session.duration / 10, 20)))
                    .foregroundStyle(syncRatioColor(session.syncRatio))
                }
                .chartYAxisLabel("Avg SNR (dB)")
                .frame(height: 150)
                
                // Legend
                HStack(spacing: 12) {
                    LegendItem(color: .green, label: ">70% sync")
                    LegendItem(color: .yellow, label: "30-70%")
                    LegendItem(color: .red, label: "<30%")
                    Text("(size = duration)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func syncRatioColor(_ ratio: Double) -> Color {
        if ratio > 0.7 { return .green }
        if ratio > 0.3 { return .yellow }
        return .red
    }
}
