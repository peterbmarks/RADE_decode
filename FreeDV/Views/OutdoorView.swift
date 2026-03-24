import SwiftUI

/// High-contrast outdoor visibility mode for strong sunlight conditions.
/// Shows only essential info: sync state, SNR, callsign — in large, bright text on pure black.
struct OutdoorView: View {
    @ObservedObject var viewModel: TransceiverViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Giant sync indicator
                Circle()
                    .fill(viewModel.isRunning ? viewModel.syncStateColor : Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .shadow(color: viewModel.isRunning ? viewModel.syncStateColor.opacity(0.6) : .clear,
                            radius: 20)
                
                Text(viewModel.isRunning ? viewModel.syncStateText.uppercased() : "IDLE")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.isRunning ? viewModel.syncStateColor : .gray)
                
                // Giant SNR display
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(viewModel.isRunning ? String(format: "%+.0f", viewModel.snr) : "--")
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("dB")
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.7))
                }
                
                // Decoded callsign — large and bright
                Text(viewModel.decodedCallsign.isEmpty ? "—" : viewModel.decodedCallsign)
                    .font(.system(size: 48, weight: .medium, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                Spacer()
                
                // Minimal Start/Stop button
                Button(action: { viewModel.toggleRunning() }) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 20))
                        Text(viewModel.isRunning ? "STOP" : "START")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        viewModel.isRunning
                            ? Color.red.opacity(0.8)
                            : Color.green.opacity(0.7)
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .persistentSystemOverlays(.hidden)
    }
}

#Preview {
    OutdoorView(viewModel: TransceiverViewModel())
}
