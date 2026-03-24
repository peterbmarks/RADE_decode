import Foundation
import SwiftData

@Model
class SyncEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var offsetMs: Int64
    var fromState: Int        // 0=SEARCH, 1=CANDIDATE, 2=SYNC
    var toState: Int
    var snrAtEvent: Float
    var freqOffsetAtEvent: Float
    
    var session: ReceptionSession?
    
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         offsetMs: Int64 = 0,
         fromState: Int = 0,
         toState: Int = 0,
         snrAtEvent: Float = 0,
         freqOffsetAtEvent: Float = 0) {
        self.id = id
        self.timestamp = timestamp
        self.offsetMs = offsetMs
        self.fromState = fromState
        self.toState = toState
        self.snrAtEvent = snrAtEvent
        self.freqOffsetAtEvent = freqOffsetAtEvent
    }
}
