import Foundation
import SwiftData

@Model
class ReceptionSession {
    @Attribute(.unique) var id: UUID
    var startTime: Date
    var endTime: Date?
    var audioDevice: String
    var sampleRateHz: Int
    var audioFilename: String?
    var audioFileSize: Int64
    var totalModemFrames: Int
    var syncedFrames: Int
    var peakSNR: Float
    var avgSNR: Float
    var callsignsDecoded: [String]
    var notes: String
    
    // GPS location at session start
    var startLatitude: Double?
    var startLongitude: Double?
    var startAltitude: Double?
    
    @Relationship(deleteRule: .cascade, inverse: \SignalSnapshot.session)
    var snapshots: [SignalSnapshot]
    
    @Relationship(deleteRule: .cascade, inverse: \SyncEvent.session)
    var syncEvents: [SyncEvent]
    
    @Relationship(deleteRule: .cascade, inverse: \CallsignEvent.session)
    var callsignEvents: [CallsignEvent]
    
    var duration: TimeInterval {
        guard let end = endTime else { return Date().timeIntervalSince(startTime) }
        let wallDuration = end.timeIntervalSince(startTime)
        // During deferred replay, wall clock is compressed (faster-than-realtime processing).
        // Use modem frame count as a floor: each RADE frame ≈ 960 samples at 8kHz = 0.12s.
        let frameDuration = Double(totalModemFrames) * 0.12
        return max(wallDuration, frameDuration)
    }
    
    var syncRatio: Double {
        guard totalModemFrames > 0 else { return 0 }
        return Double(syncedFrames) / Double(totalModemFrames)
    }
    
    init(id: UUID = UUID(),
         startTime: Date = Date(),
         audioDevice: String = "Unknown",
         sampleRateHz: Int = 48000) {
        self.id = id
        self.startTime = startTime
        self.endTime = nil
        self.audioDevice = audioDevice
        self.sampleRateHz = sampleRateHz
        self.audioFilename = nil
        self.audioFileSize = 0
        self.totalModemFrames = 0
        self.syncedFrames = 0
        self.peakSNR = -99
        self.avgSNR = 0
        self.callsignsDecoded = []
        self.notes = ""
        self.snapshots = []
        self.syncEvents = []
        self.callsignEvents = []
    }
}
