import Foundation

/// Shared state between the main app and Widget Extension.
/// Uses App Group shared UserDefaults for cross-process data sharing.
enum WidgetSharedState {
    
    /// App Group identifier — must match the App Group configured in both targets.
    static let appGroupID = "group.yakumo2683.FreeDV"
    
    /// Shared UserDefaults accessible from both the main app and widget extension.
    /// Falls back to standard UserDefaults if App Group container is not available.
    static let defaults: UserDefaults = {
        // Verify the App Group container actually exists before using it.
        // UserDefaults(suiteName:) returns non-nil even when the container
        // isn't provisioned, but read/write operations will crash.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil,
           let shared = UserDefaults(suiteName: appGroupID) {
            return shared
        }
        return .standard
    }()
    
    // Keys
    private static let kIsRunning = "widget_isRunning"
    private static let kSyncState = "widget_syncState"
    private static let kSNR = "widget_snr"
    private static let kLastCallsign = "widget_lastCallsign"
    private static let kDecodedCount = "widget_decodedCount"
    private static let kFrequencyMHz = "widget_frequencyMHz"
    private static let kLastUpdate = "widget_lastUpdate"
    private static let kTodayCallsigns = "widget_todayCallsigns"
    
    // MARK: - Write (Main App)
    
    static func update(isRunning: Bool, syncState: Int, snr: Float,
                        lastCallsign: String, frequencyMHz: String) {
        defaults.set(isRunning, forKey: kIsRunning)
        defaults.set(syncState, forKey: kSyncState)
        defaults.set(snr, forKey: kSNR)
        defaults.set(lastCallsign, forKey: kLastCallsign)
        defaults.set(frequencyMHz, forKey: kFrequencyMHz)
        defaults.set(Date().timeIntervalSince1970, forKey: kLastUpdate)
        
        // Track today's unique callsigns
        if !lastCallsign.isEmpty {
            var today = todayCallsigns
            if !today.contains(lastCallsign) {
                today.append(lastCallsign)
                defaults.set(today, forKey: kTodayCallsigns)
                defaults.set(today.count, forKey: kDecodedCount)
            }
        }
    }
    
    /// Reset today's callsign list (call at midnight or app launch on new day)
    static func resetDailyCountIfNeeded() {
        let lastDate = Date(timeIntervalSince1970: defaults.double(forKey: kLastUpdate))
        if !Calendar.current.isDateInToday(lastDate) {
            defaults.set([String](), forKey: kTodayCallsigns)
            defaults.set(0, forKey: kDecodedCount)
        }
    }
    
    // MARK: - Read (Widget)
    
    static var isRunning: Bool { defaults.bool(forKey: kIsRunning) }
    static var syncState: Int { defaults.integer(forKey: kSyncState) }
    static var snr: Float { defaults.float(forKey: kSNR) }
    static var lastCallsign: String { defaults.string(forKey: kLastCallsign) ?? "" }
    static var decodedCount: Int { defaults.integer(forKey: kDecodedCount) }
    static var frequencyMHz: String { defaults.string(forKey: kFrequencyMHz) ?? "14.236" }
    static var todayCallsigns: [String] { defaults.stringArray(forKey: kTodayCallsigns) ?? [] }
    
    static var lastUpdate: Date {
        let ts = defaults.double(forKey: kLastUpdate)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }
    
    static var lastUpdateRelative: String {
        let interval = Date().timeIntervalSince(lastUpdate)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "Over a day ago"
    }
}
