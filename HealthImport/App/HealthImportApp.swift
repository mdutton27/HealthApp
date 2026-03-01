import SwiftUI
import SwiftData

@main
struct HealthImportApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: LabResult.self)
    }
}
