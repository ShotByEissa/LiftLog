import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \AppConfig.createdAt) private var appConfigs: [AppConfig]

    var body: some View {
        Group {
            if let config = appConfigs.first {
                MainTabView(appConfig: config)
            } else {
                SetupFlowView()
            }
        }
    }
}

private struct MainTabView: View {
    var appConfig: AppConfig

    var body: some View {
        TabView {
            NavigationStack {
                WorkoutDayView(appConfig: appConfig)
            }
            .tabItem {
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
            }

            NavigationStack {
                TrendsView()
            }
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView(appConfig: appConfig)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [
            AppConfig.self,
            WorkoutDay.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            SessionEntry.self,
            LoggedSet.self,
            PlateOption.self,
            PlateCount.self
        ], inMemory: true)
}
