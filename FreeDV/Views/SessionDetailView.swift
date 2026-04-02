import SwiftUI
import SwiftData
import AVFoundation
import Observation

/// Detailed view for a single reception session with summary and charts.
struct SessionDetailView: View {
    let session: ReceptionSession
    @State private var notes: String = ""
    @State private var showShareSheet = false
    @State private var player = AudioFilePlayer()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary card
                SessionSummaryCard(session: session)
                
                // Action buttons
                HStack(spacing: 12) {
                    // Share / Export
                    Button(action: { showShareSheet = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                
                // Inline audio player
                if session.audioFilename != nil {
                    AudioPlayerView(player: player, session: session)
                }
                
                // Charts section
                ChartsSection(session: session)
                
                // Notes
                NotesSection(session: session, notes: $notes, modelContext: modelContext)
            }
            .padding()
        }
        .navigationTitle("Session Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notes = session.notes
        }
        .onDisappear {
            player.stop()
        }
        .sheet(isPresented: $showShareSheet) {
            let items = SessionExporter.shareItems(for: session)
            ShareSheet(items: items)
        }
    }
}

// MARK: - Audio File Player

@Observable
class AudioFilePlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    func load(url: URL) {
        stop()
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
        } catch {
            appLog("AudioFilePlayer: failed to load \(url.lastPathComponent): \(error)")
        }
    }
    
    func playPause() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            // Configure session for playback (not playAndRecord)
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            #endif
            player.play()
            isPlaying = true
            startTimer()
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        
        // Restore audio session to playAndRecord so RX can use the microphone
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                  options: [.allowBluetooth, .defaultToSpeaker])
        #endif
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }
    
    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
            player.currentTime = 0
            
            // Restore audio session for RX
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .measurement,
                                      options: [.allowBluetooth, .defaultToSpeaker])
            #endif
        }
    }
}

// MARK: - Audio Player View

struct AudioPlayerView: View {
    var player: AudioFilePlayer
    let session: ReceptionSession
    @State private var loaded = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 0.01)
            )
            .tint(.orange)
            
            HStack {
                // Play / Pause
                Button(action: {
                    if !loaded { loadFile() }
                    player.playPause()
                }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                }
                .tint(.orange)
                
                // Stop
                Button(action: { player.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                }
                .tint(.secondary)
                .disabled(!player.isPlaying && player.currentTime == 0)
                
                Spacer()
                
                // Time display
                Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { loadFile() }
    }
    
    private func loadFile() {
        guard let filename = session.audioFilename else { return }
        let url = WAVRecorder.recordingsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player.load(url: url)
        loaded = true
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Summary Card

struct SessionSummaryCard: View {
    let session: ReceptionSession
    
    private var displayedCallsigns: [String] {
        guard session.modelContext != nil else { return [] }
        let fromEvents = session.callsignEvents
            .map(\.callsign)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !fromEvents.isEmpty {
            return Array(NSOrderedSet(array: fromEvents)) as? [String] ?? fromEvents
        }
        return session.callsignsDecoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Time info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(session.startTime, format: .dateTime.month().day().hour().minute().second())
                        .font(.system(size: 13, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Duration")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(formatDuration(session.duration))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }
            
            Divider()
            
            // Signal quality
            HStack(spacing: 20) {
                StatItem(label: "Avg SNR", value: String(format: "%.1f dB", session.avgSNR),
                         color: snrColor(session.avgSNR))
                StatItem(label: "Peak SNR", value: String(format: "%.1f dB", session.peakSNR),
                         color: snrColor(session.peakSNR))
                StatItem(label: "Sync", value: String(format: "%.0f%%", session.syncRatio * 100),
                         color: syncColor(session.syncRatio))
            }
            
            Divider()
            
            // Device and frames
            HStack(spacing: 20) {
                StatItem(label: "Device", value: session.audioDevice, color: .primary)
                StatItem(label: "Frames", value: "\(session.totalModemFrames)", color: .primary)
                if let filename = session.audioFilename {
                    StatItem(label: "Recording", value: formatFileSize(session.audioFileSize), color: .orange)
                }
            }
            
            // Location
            if let lat = session.startLatitude, let lon = session.startLongitude {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.blue)
                    if let alt = session.startAltitude {
                        Text(String(format: "%.0fm", alt))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Callsigns
            if !displayedCallsigns.isEmpty {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text(displayedCallsigns.joined(separator: ", "))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes >= 60 {
            return String(format: "%dh%02dm%02ds", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%dm%02ds", minutes, seconds)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes > 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.0f KB", Double(bytes) / 1_000)
    }
    
    private func snrColor(_ snr: Float) -> Color {
        if snr > 6 { return .green }
        if snr > 2 { return .yellow }
        return .red
    }
    
    private func syncColor(_ ratio: Double) -> Color {
        if ratio > 0.7 { return .green }
        if ratio > 0.3 { return .yellow }
        return .red
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

// MARK: - Charts Section (placeholder, will be implemented in Phase 5)

struct ChartsSection: View {
    let session: ReceptionSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signal Charts")
                .font(.headline)
            
            if session.snapshots.isEmpty {
                Text("No signal data recorded for this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                Text("\(session.snapshots.count) data points recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Charts will be added in Phase 5
                SNRTimeChart(snapshots: session.snapshots)
                SyncTimelineChart(snapshots: session.snapshots)
                FreqOffsetChart(snapshots: session.snapshots)
                InputLevelChart(snapshots: session.snapshots)
                SNRHistogramChart(snapshots: session.snapshots)
            }
        }
    }
}

// MARK: - Notes Section

struct NotesSection: View {
    let session: ReceptionSession
    @Binding var notes: String
    let modelContext: ModelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            TextEditor(text: $notes)
                .frame(minHeight: 60)
                .padding(8)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: notes) { _, newValue in
                    session.notes = newValue
                    try? modelContext.save()
                }
        }
    }
}
