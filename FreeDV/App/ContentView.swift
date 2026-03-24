import SwiftUI

struct ContentView: View {
    @State private var reporter = FreeDVReporter()
    @State private var powerManager = PowerManager()
    
    var body: some View {
        TabView {
            TransceiverView(reporter: reporter, powerManager: powerManager)
                .tabItem {
                    Label("Receiver", systemImage: "antenna.radiowaves.left.and.right")
                }
            
            ReporterStationsView(reporter: reporter)
                .tabItem {
                    Label("Stations", systemImage: "globe")
                }
            
            ReceptionLogView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet.rectangle")
                }
            
            NavigationStack {
                ReceptionMapView()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            
            NavigationStack {
                SettingsView(reporter: reporter, powerManager: powerManager)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
