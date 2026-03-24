import UIKit

/// Provides haptic feedback for key transceiver events.
/// Three-tier feedback: sync/unsync (impact), callsign (notification), strong signal (light impact).
class HapticManager {
    static let shared = HapticManager()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    
    /// User preference — persisted in UserDefaults
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticEnabled") }
    }
    
    private init() {}
    
    /// Pre-warm the haptic engines for lower latency on next trigger.
    func prepare() {
        guard isEnabled else { return }
        impactLight.prepare()
        impactMedium.prepare()
        notification.prepare()
    }
    
    /// SEARCH -> SYNC: medium impact — "signal locked"
    func onSync() {
        guard isEnabled else { return }
        appLog("Haptic: onSync")
        impactMedium.impactOccurred()
    }
    
    /// SYNC -> SEARCH: warning notification — "signal lost"
    func onUnsync() {
        guard isEnabled else { return }
        appLog("Haptic: onUnsync")
        notification.notificationOccurred(.warning)
    }
    
    /// Callsign decoded: success notification — "callsign received"
    func onCallsign() {
        guard isEnabled else { return }
        appLog("Haptic: onCallsign")
        notification.notificationOccurred(.success)
    }
    
    /// SNR > 20 dB: very light impact — background awareness
    func onStrongSignal() {
        guard isEnabled else { return }
        impactLight.impactOccurred(intensity: 0.4)
    }
}
