import SwiftUI
import Charts

/// SNR over time chart with quality zone backgrounds.
struct SNRTimeChart: View {
    let snapshots: [SignalSnapshot]
    
    private var displayData: [SignalSnapshot] {
        downsample(snapshots.sorted { $0.offsetMs < $1.offsetMs }, targetPoints: 400)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SNR over Time")
                .font(.system(size: 13, weight: .semibold))
            
            Chart {
                // Quality zone backgrounds
                RectangleMark(
                    xStart: nil, xEnd: nil,
                    yStart: .value("", 6), yEnd: .value("", 40)
                )
                .foregroundStyle(Color.green.opacity(0.05))
                
                RectangleMark(
                    xStart: nil, xEnd: nil,
                    yStart: .value("", 2), yEnd: .value("", 6)
                )
                .foregroundStyle(Color.yellow.opacity(0.05))
                
                RectangleMark(
                    xStart: nil, xEnd: nil,
                    yStart: .value("", -5), yEnd: .value("", 2)
                )
                .foregroundStyle(Color.red.opacity(0.05))
                
                // SNR line
                ForEach(displayData, id: \.id) { snap in
                    LineMark(
                        x: .value("Time", Double(snap.offsetMs) / 1000.0),
                        y: .value("SNR", snap.snr)
                    )
                    .foregroundStyle(snrColor(snap.snr))
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: -5...40)
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel("dB")
            .frame(height: 180)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func snrColor(_ snr: Float) -> Color {
        if snr > 6 { return .green }
        if snr > 2 { return .yellow }
        return .red
    }
}

/// Downsample an array to at most targetPoints using simple stride.
func downsample(_ data: [SignalSnapshot], targetPoints: Int) -> [SignalSnapshot] {
    guard data.count > targetPoints else { return data }
    let step = max(data.count / targetPoints, 1)
    return stride(from: 0, to: data.count, by: step).map { data[$0] }
}
