import SwiftUI

@main
struct LiftLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(PersistenceController.sharedModelContainer)
    }
}
