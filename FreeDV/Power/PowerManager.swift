import UIKit

/// Manages power profiles to optimize battery life for portable SWL operation.
/// Controls UI update rate, FFT/waterfall display, and auto-switches on low battery.
@Observable
class PowerManager {
    
    enum PowerProfile: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case balanced = "Balanced"
        case lowPower = "Low Power"
        case ultraLow = "Ultra Low"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .performance: return "Full features, highest CPU"
            case .balanced: return "Default, good balance"
            case .lowPower: return "No waterfall, slower updates"
            case .ultraLow: return "Decode only, minimal UI"
            }
        }
        
        var icon: String {
            switch self {
            case .performance: return "bolt.fill"
            case .balanced: return "battery.75percent"
            case .lowPower: return "battery.25percent"
            case .ultraLow: return "battery.0percent"
            }
        }
    }
    
    // MARK: - Current Profile
    
    var currentProfile: PowerProfile = .balanced {
        didSet {
            guard didFinishInit else { return }
            UserDefaults.standard.set(currentProfile.rawValue, forKey: "powerProfile")
            applyProfile(currentProfile)
        }
    }
    
    // MARK: - Profile-Controlled Settings
    
    /// Status timer interval in seconds (controls UI update rate)
    private(set) var uiUpdateInterval: TimeInterval = 0.15
    /// Whether FFT spectrum is computed and displayed
    private(set) var fftEnabled: Bool = true
    /// Whether waterfall display is updated
    private(set) var waterfallEnabled: Bool = true
    
    // MARK: - Battery State
    
    private(set) var batteryLevel: Float = 1.0
    private(set) var batteryState: UIDevice.BatteryState = .unknown
    var autoSwitchEnabled: Bool = true {
        didSet {
            guard didFinishInit else { return }
            UserDefaults.standard.set(autoSwitchEnabled, forKey: "powerAutoSwitch")
        }
    }
    
    /// Whether profile was auto-switched by battery monitor (not user choice)
    @ObservationIgnored
    private var isAutoSwitched = false
    
    @ObservationIgnored
    private var didFinishInit = false
    
    // MARK: - Init
    
    init() {
        // Restore saved preferences
        if let saved = UserDefaults.standard.string(forKey: "powerProfile"),
           let profile = PowerProfile(rawValue: saved) {
            currentProfile = profile
        }
        autoSwitchEnabled = UserDefaults.standard.object(forKey: "powerAutoSwitch") as? Bool ?? true
        
        applyProfile(currentProfile)
        startBatteryMonitoring()
        didFinishInit = true
    }
    
    // MARK: - Profile Application
    
    private func applyProfile(_ profile: PowerProfile) {
        switch profile {
        case .performance:
            uiUpdateInterval = 0.1    // 10 Hz
            fftEnabled = true
            waterfallEnabled = true
            
        case .balanced:
            uiUpdateInterval = 0.15   // ~7 Hz
            fftEnabled = true
            waterfallEnabled = true
            
        case .lowPower:
            uiUpdateInterval = 0.25   // 4 Hz
            fftEnabled = true
            waterfallEnabled = false
            
        case .ultraLow:
            uiUpdateInterval = 0.5    // 2 Hz
            fftEnabled = false
            waterfallEnabled = false
        }
    }
    
    // MARK: - Battery Monitoring
    
    private func startBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleBatteryChange()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.batteryState = UIDevice.current.batteryState
        }
    }
    
    private func handleBatteryChange() {
        batteryLevel = UIDevice.current.batteryLevel
        
        guard autoSwitchEnabled,
              batteryState == .unplugged else { return }
        
        // Auto-switch to power saving profiles on low battery
        if batteryLevel < 0.1 && currentProfile != .ultraLow {
            currentProfile = .ultraLow
            isAutoSwitched = true
        } else if batteryLevel < 0.2 && currentProfile == .performance {
            currentProfile = .lowPower
            isAutoSwitched = true
        } else if batteryLevel < 0.2 && currentProfile == .balanced {
            currentProfile = .lowPower
            isAutoSwitched = true
        }
    }
    
    /// Battery level as a formatted percentage string
    var batteryPercentage: String {
        if batteryLevel < 0 { return "Unknown" }
        return "\(Int(batteryLevel * 100))%"
    }
    
    var isCharging: Bool {
        batteryState == .charging || batteryState == .full
    }
}
