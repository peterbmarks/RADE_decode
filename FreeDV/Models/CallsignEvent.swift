import Foundation
import SwiftData

@Model
class CallsignEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var offsetMs: Int64
    var callsign: String
    var snrAtDecode: Float
    var modemFrame: Int
    
    // GPS location at time of decode
    var latitude: Double?
    var longitude: Double?
    
    var session: ReceptionSession?
    
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         offsetMs: Int64 = 0,
         callsign: String = "",
         snrAtDecode: Float = 0,
         modemFrame: Int = 0) {
        self.id = id
        self.timestamp = timestamp
        self.offsetMs = offsetMs
        self.callsign = callsign
        self.snrAtDecode = snrAtDecode
        self.modemFrame = modemFrame
    }
}
