import Foundation

/// Exports session data as CSV and provides file URLs for sharing.
class SessionExporter {
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    /// Export all snapshots as a CSV file. Returns the temporary file URL.
    static func exportCSV(session: ReceptionSession) -> URL {
        let filename = "rade_log_\(session.id.uuidString.prefix(8)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        var csv = "timestamp_utc,offset_ms,snr_db,freq_offset_hz,sync_state,input_level_db,output_level_db,nin,clock_offset\n"
        
        let sorted = session.snapshots.sorted { $0.offsetMs < $1.offsetMs }
        for snap in sorted {
            csv += "\(isoFormatter.string(from: snap.timestamp)),"
            csv += "\(snap.offsetMs),"
            csv += "\(String(format: "%.2f", snap.snr)),"
            csv += "\(String(format: "%.2f", snap.freqOffset)),"
            csv += "\(snap.syncState),"
            csv += "\(String(format: "%.1f", snap.inputLevelDb)),"
            csv += "\(String(format: "%.1f", snap.outputLevelDb)),"
            csv += "\(snap.nin),"
            csv += "\(String(format: "%.3f", snap.clockOffset))\n"
        }
        
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    /// Get all shareable files for a session (CSV + WAV if available).
    static func shareItems(for session: ReceptionSession) -> [URL] {
        var items: [URL] = []
        
        // CSV data
        items.append(exportCSV(session: session))
        
        // WAV recording (if available)
        if let audioFile = session.audioFilename {
            let audioURL = WAVRecorder.recordingsDirectory.appendingPathComponent(audioFile)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                items.append(audioURL)
            }
        }
        
        return items
    }
}
