import SwiftUI
import SwiftData

@main
struct NightPayCheckApp: App {
    private let container: Result<ModelContainer, Error> = Result {
        let schema = Schema([NightSnapshot.self])
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let inMemory = false
        #endif
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                ContentView().modelContainer(container)
            case .failure:
                ContentUnavailableView("Local storage couldn't open", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your records have not been replaced. Restart the app and check available device storage."))
            }
        }
    }
}
