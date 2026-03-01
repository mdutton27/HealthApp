import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Results", systemImage: "list.clipboard")
                }
                .tag(0)

            ImportView()
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .tag(1)
        }
        .task {
            await HealthKitManager.shared.requestAuthorization()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: LabResult.self, inMemory: true)
}
