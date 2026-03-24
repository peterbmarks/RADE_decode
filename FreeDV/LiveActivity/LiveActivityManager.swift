import ActivityKit
import Foundation

/// Manages the FreeDV Live Activity lifecycle (start, update, end).
/// Called from TransceiverViewModel when RX state changes.
@MainActor
class LiveActivityManager {
    
    private var currentActivity: Activity<FreeDVAttributes>?
    private var decodedCount: Int = 0
    private var isUpdating = false
    
    /// How long before the Live Activity shows as stale if the app stops updating.
    /// If the app is killed by iOS, the activity will go stale after this interval.
    private let staleTimeout: TimeInterval = 5 * 60  // 5 minutes
    
    /// Whether Live Activities are supported and enabled
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    /// End any Live Activities left over from a previous app session (crash/kill).
    /// Call this on app launch.
    func cleanupStaleActivities() {
        Task {
            for activity in Activity<FreeDVAttributes>.activities {
                let finalState = FreeDVAttributes.ContentState(
                    syncState: 0, snr: 0, freqOffsetHz: 0,
                    lastCallsign: "", decodedCount: 0, isRunning: false
                )
                let content = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }
    
    /// Start a new Live Activity when RX begins.
    func startActivity(frequencyMHz: String) {
        guard isAvailable else {
            appLog("Live Activity: not available on this device")
            return
        }
        
        // End any existing activity first
        endActivity()
        
        let attributes = FreeDVAttributes(
            frequencyMHz: frequencyMHz,
            startTime: Date()
        )
        
        let initialState = FreeDVAttributes.ContentState(
            syncState: 0,
            snr: 0,
            freqOffsetHz: 0,
            lastCallsign: "",
            decodedCount: 0,
            isRunning: true
        )
        
        decodedCount = 0
        
        let content = ActivityContent(state: initialState,
                                       staleDate: Date().addingTimeInterval(staleTimeout))
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil  // Local only, no push notifications
            )
            appLog("Live Activity: started (id=\(currentActivity?.id ?? "nil"))")
        } catch {
            appLog("Live Activity: failed to start — \(error.localizedDescription)")
        }
    }
    
    /// Update the Live Activity with current transceiver state.
    func updateActivity(syncState: Int, snr: Float, freqOffsetHz: Float, lastCallsign: String) {
        guard let activity = currentActivity else { return }
        
        // Increment decoded count on new callsign
        if !lastCallsign.isEmpty {
            decodedCount += 1
        }
        
        let updatedState = FreeDVAttributes.ContentState(
            syncState: syncState,
            snr: snr,
            freqOffsetHz: freqOffsetHz,
            lastCallsign: lastCallsign,
            decodedCount: decodedCount,
            isRunning: true
        )
        
        let content = ActivityContent(state: updatedState,
                                       staleDate: Date().addingTimeInterval(staleTimeout))
        
        // Prevent Task accumulation — skip if previous update is still in progress
        guard !isUpdating else { return }
        isUpdating = true
        Task {
            await activity.update(content)
            self.isUpdating = false
        }
    }
    
    /// End the Live Activity when RX stops.
    func endActivity() {
        guard let activity = currentActivity else { return }
        
        let finalState = FreeDVAttributes.ContentState(
            syncState: 0,
            snr: 0,
            freqOffsetHz: 0,
            lastCallsign: "",
            decodedCount: decodedCount,
            isRunning: false
        )
        
        let content = ActivityContent(state: finalState, staleDate: nil)
        
        Task {
            await activity.end(content, dismissalPolicy: .after(.now + 60))
            appLog("Live Activity: ended")
        }
        
        currentActivity = nil
        decodedCount = 0
    }
}
