import ActivityKit
import Foundation

/// Defines the data model for FreeDV Live Activity on Lock Screen and Dynamic Island.
struct FreeDVAttributes: ActivityAttributes {
    
    /// Dynamic state that updates during the activity's lifecycle.
    struct ContentState: Codable, Hashable {
        /// Sync state: 0=SEARCH, 1=CANDIDATE, 2=SYNCED
        var syncState: Int
        /// Current SNR in dB
        var snr: Float
        /// Frequency offset in Hz
        var freqOffsetHz: Float
        /// Last decoded callsign (empty if none)
        var lastCallsign: String
        /// Total callsigns decoded in this session
        var decodedCount: Int
        /// Whether the receiver is actively running
        var isRunning: Bool
    }
    
    /// Static attributes set when the activity starts (don't change).
    var frequencyMHz: String
    var startTime: Date
}
