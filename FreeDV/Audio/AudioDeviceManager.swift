import SwiftUI
import AVFoundation
import Combine

#if os(iOS)
/// Represents an available audio output device.
struct OutputDevice: Identifiable {
    let id: String          // "default" or "speaker"
    let name: String        // Display name
    let portType: String    // Port type description
    let isSpeaker: Bool     // True if built-in speaker override
}
#endif

/// Manages iOS audio device enumeration and routing.
class AudioDeviceManager: ObservableObject {
    
    @Published var currentInputName: String = "Unknown"
    @Published var currentOutputName: String = "Unknown"
    
    #if os(iOS)
    @Published var availableInputs: [AVAudioSessionPortDescription] = []
    @Published var availableOutputs: [OutputDevice] = []
    @Published var selectedOutputId: String = "default"
    

    #endif
    
    init() {
        #if os(iOS)
        updateDeviceInfo()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        #else
        currentInputName = "Default Input"
        currentOutputName = "Default Output"
        #endif
    }
    
    func updateDeviceInfo() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        DispatchQueue.main.async {
            self.currentInputName = route.inputs.first?.portName ?? "None"
            self.currentOutputName = route.outputs.first?.portName ?? "None"
            self.availableInputs = session.availableInputs ?? []
            self.buildOutputList(route: route)
        }
        #endif
    }
    
    #if os(iOS)
    /// Build available output device list from current route.
    private func buildOutputList(route: AVAudioSessionRouteDescription) {
        var outputs: [OutputDevice] = []
        
        // Add currently routed output as "default"
        if let current = route.outputs.first {
            // If current output IS the speaker, don't add it twice
            if current.portType != .builtInSpeaker {
                outputs.append(OutputDevice(
                    id: "default",
                    name: current.portName,
                    portType: current.portType.rawValue,
                    isSpeaker: false
                ))
            }
        }
        
        // Always offer built-in speaker
        outputs.append(OutputDevice(
            id: "speaker",
            name: "iPhone Speaker",
            portType: "Built-in Speaker",
            isSpeaker: true
        ))
        
        availableOutputs = outputs
    }
    
    /// Select an output device.
    /// Note: iOS treats USB audio as a paired input+output route.
    /// Switching output to speaker also changes input to built-in mic.
    /// There is no way to use USB input + speaker output simultaneously.
    func selectOutput(_ device: OutputDevice) {
        let session = AVAudioSession.sharedInstance()
        
        do {
            if device.isSpeaker {
                try session.overrideOutputAudioPort(.speaker)
                selectedOutputId = "speaker"
                appLog("Output → Speaker (input also changed to built-in mic)")
            } else {
                try session.overrideOutputAudioPort(.none)
                selectedOutputId = "default"
                appLog("Output → \(device.name)")
            }
            updateDeviceInfo()
        } catch {
            appLog("selectOutput FAILED: \(error)")
        }
    }
    
    /// Select a specific input port (e.g., USB audio device)
    func selectInput(_ port: AVAudioSessionPortDescription) {
        do {
            try AVAudioSession.sharedInstance().setPreferredInput(port)
            updateDeviceInfo()
        } catch {
            print("Failed to select input: \(error)")
        }
    }
    
    @objc private func routeChanged(_ notification: Notification) {
        updateDeviceInfo()
    }
    #endif
}
