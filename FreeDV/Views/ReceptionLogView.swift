import SwiftUI
import SwiftData

/// Session list showing all recorded reception sessions.
struct ReceptionLogView: View {
    @Query(sort: \ReceptionSession.startTime, order: .reverse)
    private var sessions: [ReceptionSession]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Reception sessions will appear here after you start receiving.")
                    )
                } else {
                    List {
                        // Session overview chart at top
                        if sessions.count >= 2 {
                            Section {
                                SessionOverviewChart(sessions: sessions)
                            }
                        }
                        
                        // Session list
                        Section("Sessions") {
                            ForEach(sessions) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    SessionRowView(session: session)
                                }
                            }
                            .onDelete(perform: deleteSessions)
                        }
                    }
                }
            }
            .navigationTitle("Reception Log")
        }
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            // Delete associated WAV file
            if let filename = session.audioFilename {
                let url = WAVRecorder.recordingsDirectory.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: ReceptionSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top line: date + duration
            HStack {
                Text(session.startTime, style: .date)
                    .font(.system(size: 14, weight: .medium))
                Text(session.startTime, style: .time)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(session.duration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            // Middle line: SNR + sync ratio + device
            HStack(spacing: 12) {
                // Average SNR
                HStack(spacing: 3) {
                    Text("SNR")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", session.avgSNR))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(snrColor(session.avgSNR))
                }
                
                // Sync ratio mini bar
                HStack(spacing: 3) {
                    Text("SYNC")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    SyncRatioBar(ratio: session.syncRatio)
                        .frame(width: 40, height: 8)
                    Text(String(format: "%.0f%%", session.syncRatio * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Recording indicator
                if session.audioFilename != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            
            // Bottom line: callsigns (if any)
            if !session.callsignsDecoded.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(session.callsignsDecoded.joined(separator: ", "))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%dh%02dm", hours, mins)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func snrColor(_ snr: Float) -> Color {
        if snr > 6 { return .green }
        if snr > 2 { return .yellow }
        return .red
    }
}

// MARK: - Sync Ratio Bar

struct SyncRatioBar: View {
    let ratio: Double
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(min(ratio, 1.0)))
            }
        }
    }
    
    private var barColor: Color {
        if ratio > 0.7 { return .green }
        if ratio > 0.3 { return .yellow }
        return .red
    }
}
