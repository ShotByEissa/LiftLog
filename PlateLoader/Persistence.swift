import SwiftData

enum PersistenceController {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AppConfig.self,
            WorkoutDay.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            SessionEntry.self,
            LoggedSet.self,
            PlateOption.self,
            PlateCount.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }()
}
