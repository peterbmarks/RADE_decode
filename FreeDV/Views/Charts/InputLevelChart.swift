import SwiftUI
import Charts

/// Input audio level over time with clipping/weak zone indicators.
struct InputLevelChart: View {
    let snapshots: [SignalSnapshot]
    
    private var displayData: [SignalSnapshot] {
        downsample(snapshots.sorted { $0.offsetMs < $1.offsetMs }, targetPoints: 400)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Input Level")
                .font(.system(size: 13, weight: .semibold))
            
            Chart {
                // Clipping danger zone
                RectangleMark(
                    xStart: nil, xEnd: nil,
                    yStart: .value("", -3), yEnd: .value("", 0)
                )
                .foregroundStyle(Color.red.opacity(0.08))
                
                // Weak signal zone
                RectangleMark(
                    xStart: nil, xEnd: nil,
                    yStart: .value("", -60), yEnd: .value("", -40)
                )
                .foregroundStyle(Color.gray.opacity(0.08))
                
                // Level line
                ForEach(displayData, id: \.id) { snap in
                    AreaMark(
                        x: .value("Time", Double(snap.offsetMs) / 1000.0),
                        y: .value("dB", snap.inputLevelDb)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    
                    LineMark(
                        x: .value("Time", Double(snap.offsetMs) / 1000.0),
                        y: .value("dB", snap.inputLevelDb)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .chartYScale(domain: -60...0)
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel("dBFS")
            .frame(height: 120)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
