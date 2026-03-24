import Foundation
import SwiftData

@Model
class SignalSnapshot {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var offsetMs: Int64
    var snr: Float
    var freqOffset: Float
    var syncState: Int        // 0=SEARCH, 1=CANDIDATE, 2=SYNC
    var inputLevelDb: Float
    var outputLevelDb: Float
    var nin: Int
    var clockOffset: Float
    
    var session: ReceptionSession?
    
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         offsetMs: Int64 = 0,
         snr: Float = 0,
         freqOffset: Float = 0,
         syncState: Int = 0,
         inputLevelDb: Float = -60,
         outputLevelDb: Float = -60,
         nin: Int = 960,
         clockOffset: Float = 0) {
        self.id = id
        self.timestamp = timestamp
        self.offsetMs = offsetMs
        self.snr = snr
        self.freqOffset = freqOffset
        self.syncState = syncState
        self.inputLevelDb = inputLevelDb
        self.outputLevelDb = outputLevelDb
        self.nin = nin
        self.clockOffset = clockOffset
    }
}
