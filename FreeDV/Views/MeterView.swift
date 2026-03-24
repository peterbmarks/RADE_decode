import SwiftUI

/// A segmented LED-style horizontal level meter showing audio level in dB.
struct MeterView: View {
    let label: String
    let level: Float  // dB, typically -60 to 0
    
    private let minDB: Float = -60
    private let maxDB: Float = 0
    private let segmentCount = 30
    
    private var normalizedLevel: CGFloat {
        CGFloat((level - minDB) / (maxDB - minDB)).clamped(to: 0...1)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            
            // Segmented LED bar
            HStack(spacing: 1) {
                ForEach(0..<segmentCount, id: \.self) { i in
                    let fraction = CGFloat(i) / CGFloat(segmentCount)
                    let isLit = fraction < normalizedLevel
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(segmentColor(at: fraction, lit: isLit))
                }
            }
            .frame(height: 10)
            
            Text(String(format: "%3.0f", level))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
    
    private func segmentColor(at fraction: CGFloat, lit: Bool) -> Color {
        if !lit {
            return Color.white.opacity(0.06)
        }
        // Green 0-70%, Yellow 70-85%, Red 85-100%
        if fraction < 0.70 {
            return Color.green
        } else if fraction < 0.85 {
            return Color.yellow
        } else {
            return Color.red
        }
    }
}

#Preview {
    VStack(spacing: 6) {
        MeterView(label: "IN", level: -25)
        MeterView(label: "OUT", level: -10)
        MeterView(label: "PEAK", level: -3)
    }
    .padding()
    .background(.black)
}
