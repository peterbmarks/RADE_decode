import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation
import Combine

/// Settings page for audio device selection and app configuration.
struct SettingsView: View {
    @Bindable var reporter: FreeDVReporter
    var powerManager: PowerManager
    @StateObject private var deviceManager = AudioDeviceManager()
    @StateObject private var locationHelper = LocationHelper()
    
    var body: some View {
        Form {
            // FreeDV Reporter section
            Section("FreeDV Reporter") {
                Toggle("Enable Reporting", isOn: $reporter.isEnabled)
                
                if reporter.isEnabled {
                    HStack {
                        Text("Callsign")
                        Spacer()
                        TextField("e.g. BV2ABC", text: $reporter.callsign)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                    }
                    
                    HStack {
                        Text("Grid Square")
                        Spacer()
                        TextField("e.g. PL04qf", text: $reporter.gridSquare)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                        Button {
                            locationHelper.requestLocation { grid in
                                reporter.gridSquare = grid
                            }
                        } label: {
                            Image(systemName: locationHelper.isLocating
                                  ? "location.fill" : "location")
                        }
                        .disabled(locationHelper.isLocating)
                    }
                    
                    NavigationLink {
                        FrequencyPickerView(frequencyHz: $reporter.frequencyHz)
                    } label: {
                        LabeledContent("Frequency", value: formatFrequency(reporter.frequencyHz))
                    }
                    
                    HStack {
                        Text("Status Message")
                        Spacer()
                        TextField("Optional", text: $reporter.statusMessage)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                    }
                    
                    // Connection status
                    HStack {
                        Text("Connection")
                        Spacer()
                        if reporter.isConnected {
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Text(reporter.isReady ? "Connected" : "Connecting...")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(.gray).frame(width: 8, height: 8)
                                Text("Disconnected")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                    
                    // Online station count
                    if reporter.isConnected {
                        LabeledContent("Online Stations", value: "\(reporter.stations.count)")
                    }
                }
            }
            
            // Audio devices section
            Section("Audio Devices") {
                HStack {
                    Text("Input")
                    Spacer()
                    Text(deviceManager.currentInputName)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Output")
                    Spacer()
                    Text(deviceManager.currentOutputName)
                        .foregroundStyle(.secondary)
                }
                
                #if os(iOS)
                if !deviceManager.availableInputs.isEmpty {
                    NavigationLink("Select Input Device") {
                        InputDevicePickerView(deviceManager: deviceManager)
                    }
                }
                if !deviceManager.availableOutputs.isEmpty {
                    NavigationLink("Select Output Device") {
                        OutputDevicePickerView(deviceManager: deviceManager)
                    }
                }
                #endif
            }
            
            // Power management
            Section("Power Profile") {
                Picker("Profile", selection: Binding(
                    get: { powerManager.currentProfile },
                    set: { powerManager.currentProfile = $0 }
                )) {
                    ForEach(PowerManager.PowerProfile.allCases) { profile in
                        Label(profile.rawValue, systemImage: profile.icon)
                            .tag(profile)
                    }
                }
                
                if powerManager.currentProfile != .balanced {
                    Text(powerManager.currentProfile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Toggle("Auto-switch on low battery", isOn: Binding(
                    get: { powerManager.autoSwitchEnabled },
                    set: { powerManager.autoSwitchEnabled = $0 }
                ))
                
                HStack {
                    Text("Battery")
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: powerManager.isCharging ? "battery.100percent.bolt" : "battery.50percent")
                            .foregroundStyle(powerManager.batteryLevel < 0.2 ? .red : .green)
                        Text(powerManager.batteryPercentage)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
            
            // Haptic feedback
            Section("Haptic Feedback") {
                Toggle("Enable Haptics", isOn: Binding(
                    get: { HapticManager.shared.isEnabled },
                    set: { HapticManager.shared.isEnabled = $0 }
                ))
                if HapticManager.shared.isEnabled {
                    LabeledContent("Sync locked", value: "Medium tap")
                    LabeledContent("Signal lost", value: "Warning")
                    LabeledContent("Callsign decoded", value: "Success")
                    LabeledContent("Strong signal (>20dB)", value: "Light tap")
                }
            }
            
            // GPS tracking
            Section("GPS Tracking") {
                Toggle("Track Location During RX", isOn: Binding(
                    get: { AudioManager.gpsTrackingEnabled },
                    set: { AudioManager.gpsTrackingEnabled = $0 }
                ))
                Text("Records your location when receiving signals. Useful for comparing reception at different locations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Recording settings
            Section("Reception Log") {
                // Auto-record toggle uses @AppStorage
                RecordingSettingsSection()
            }
            
            // RADE info section
            Section("RADE Info") {
                LabeledContent("Modem Sample Rate", value: "8000 Hz")
                LabeledContent("Speech Sample Rate", value: "16000 Hz")
                LabeledContent("OFDM Carriers", value: "30")
                LabeledContent("Bandwidth", value: "~1.3 kHz")
                LabeledContent("Modem Frame", value: "120 ms")
            }
            
            // About section
            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                LabeledContent("License", value: "BSD-2-Clause")
                Link("FreeDV Project", destination: URL(string: "https://freedv.org")!)
            }
        }
        .navigationTitle("Settings")
        .onDisappear {
            // Send updated status message when leaving settings
            if reporter.isReady {
                reporter.sendMessageUpdate()
            }
        }
    }
    
    private func formatFrequency(_ hz: UInt64) -> String {
        String(format: "%.3f MHz", Double(hz) / 1_000_000)
    }
}

// MARK: - Frequency Picker

struct FrequencyPickerView: View {
    @Binding var frequencyHz: UInt64
    @State private var customKHz: String = ""
    
    let commonFrequencies: [(String, UInt64)] = [
        ("20m – 14.236 MHz", 14_236_000),
        ("40m – 7.177 MHz",   7_177_000),
        ("80m – 3.625 MHz",   3_625_000),
        ("15m – 21.313 MHz", 21_313_000),
        ("10m – 28.330 MHz", 28_330_000),
        ("17m – 18.118 MHz", 18_118_000),
    ]
    
    var body: some View {
        List {
            Section("Common Frequencies") {
                ForEach(commonFrequencies, id: \.1) { name, freq in
                    Button {
                        frequencyHz = freq
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if frequencyHz == freq {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            
            Section("Custom Frequency") {
                HStack {
                    Text("kHz")
                    TextField("14236", text: $customKHz)
                        .keyboardType(.decimalPad)
                    Button("Set") {
                        if let kHz = Double(customKHz) {
                            frequencyHz = UInt64(kHz * 1000)
                        }
                    }
                    .disabled(customKHz.isEmpty)
                }
            }
            
            Section {
                LabeledContent("Current", value: String(format: "%.3f MHz", Double(frequencyHz) / 1_000_000))
            }
        }
        .navigationTitle("Frequency")
    }
}

#if os(iOS)
/// Picker for selecting audio output device
struct OutputDevicePickerView: View {
    @ObservedObject var deviceManager: AudioDeviceManager
    
    var body: some View {
        List(deviceManager.availableOutputs) { device in
            Button(action: {
                deviceManager.selectOutput(device)
            }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                        Text(device.portType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if device.id == deviceManager.selectedOutputId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle("Output Device")
    }
}

/// Picker for selecting audio input device
struct InputDevicePickerView: View {
    @ObservedObject var deviceManager: AudioDeviceManager
    
    var body: some View {
        List(deviceManager.availableInputs, id: \.uid) { port in
            Button(action: {
                deviceManager.selectInput(port)
            }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(port.portName)
                        Text(port.portType.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if port.portName == deviceManager.currentInputName {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle("Input Device")
    }
}
#endif

// MARK: - Recording Settings

struct RecordingSettingsSection: View {
    @AppStorage("autoRecordEnabled") private var autoRecordEnabled = true
    @AppStorage("maxStorageMB") private var maxStorageMB = 2000  // 2 GB default
    @Environment(\.modelContext) private var modelContext
    @State private var usedSpace: String = "Calculating..."
    @State private var showClearConfirm = false
    
    var body: some View {
        Toggle("Auto Record WAV", isOn: $autoRecordEnabled)
        
        Picker("Max Storage", selection: $maxStorageMB) {
            Text("500 MB").tag(500)
            Text("1 GB").tag(1000)
            Text("2 GB").tag(2000)
            Text("5 GB").tag(5000)
        }
        
        LabeledContent("Used Space", value: usedSpace)
            .onAppear { updateUsedSpace() }
        
        Button("Delete All Recordings", role: .destructive) {
            showClearConfirm = true
        }
        .confirmationDialog("Delete all recordings and session data?", isPresented: $showClearConfirm) {
            Button("Delete All", role: .destructive) {
                clearRecordings()
            }
        }
    }
    
    private func updateUsedSpace() {
        let bytes = WAVRecorder.totalRecordingsSize
        if bytes > 1_000_000 {
            usedSpace = String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else {
            usedSpace = String(format: "%.0f KB", Double(bytes) / 1_000)
        }
    }
    
    private func clearRecordings() {
        // Delete WAV files from disk
        let dir = WAVRecorder.recordingsDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        
        // Delete all ReceptionSession records from SwiftData
        // (cascade deletes associated snapshots, sync events, and callsign events)
        do {
            try modelContext.delete(model: ReceptionSession.self)
            try modelContext.save()
        } catch {
            appLog("Failed to delete session records: \(error)")
        }
        
        updateUsedSpace()
    }
}

// MARK: - Location Helper

/// Requests a single location fix and converts it to a Maidenhead grid square.
class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLocating = false
    
    private let manager = CLLocationManager()
    private var completion: ((String) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func requestLocation(completion: @escaping (String) -> Void) {
        self.completion = completion
        isLocating = true
        
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            isLocating = false
            self.completion = nil
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            if isLocating {
                manager.requestLocation()
            }
        } else if manager.authorizationStatus == .denied ||
                  manager.authorizationStatus == .restricted {
            isLocating = false
            completion = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let grid = Self.maidenhead(latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude)
        DispatchQueue.main.async {
            self.completion?(grid)
            self.isLocating = false
            self.completion = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        appLog("Location error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isLocating = false
            self.completion = nil
        }
    }
    
    /// Convert latitude/longitude to 6-character Maidenhead grid locator.
    static func maidenhead(latitude: Double, longitude: Double) -> String {
        let lon = longitude + 180.0
        let lat = latitude + 90.0
        
        // Field (2 uppercase letters)
        let fieldLon = Int(lon / 20.0)
        let fieldLat = Int(lat / 10.0)
        
        // Square (2 digits)
        let squareLon = Int((lon - Double(fieldLon) * 20.0) / 2.0)
        let squareLat = Int((lat - Double(fieldLat) * 10.0) / 1.0)
        
        // Subsquare (2 lowercase letters)
        let subLon = Int(((lon - Double(fieldLon) * 20.0 - Double(squareLon) * 2.0) / 2.0) * 24.0)
        let subLat = Int(((lat - Double(fieldLat) * 10.0 - Double(squareLat) * 1.0) / 1.0) * 24.0)
        
        let f1 = Character(UnicodeScalar(65 + min(fieldLon, 17))!)
        let f2 = Character(UnicodeScalar(65 + min(fieldLat, 17))!)
        let s1 = Character(UnicodeScalar(48 + min(squareLon, 9))!)
        let s2 = Character(UnicodeScalar(48 + min(squareLat, 9))!)
        let sub1 = Character(UnicodeScalar(97 + min(subLon, 23))!)
        let sub2 = Character(UnicodeScalar(97 + min(subLat, 23))!)
        
        return String([f1, f2, s1, s2, sub1, sub2])
    }
}

#Preview {
    NavigationStack {
        SettingsView(reporter: FreeDVReporter(), powerManager: PowerManager())
    }
}
