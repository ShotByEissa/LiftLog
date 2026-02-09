import SwiftUI

@main
struct PlateLoaderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(PersistenceController.sharedModelContainer)
    }
}
