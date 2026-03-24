import SwiftUI
import SwiftData

@main
struct FreeDVApp: App {
    let container: ModelContainer
    
    init() {
        let schema = Schema([
            ReceptionSession.self,
            SignalSnapshot.self,
            SyncEvent.self,
            CallsignEvent.self
        ])
        let config = ModelConfiguration(
            "ReceptionLog",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appLog("App: foreground (active)")
            case .inactive:
                appLog("App: inactive")
            case .background:
                appLog("App: background — audio continues if RX is running")
            @unknown default:
                break
            }
        }
    }
}
