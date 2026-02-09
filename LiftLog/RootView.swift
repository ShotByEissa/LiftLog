import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \AppConfig.createdAt) private var appConfigs: [AppConfig]
    @Query private var splitPlans: [SplitPlan]

    var body: some View {
        Group {
            if let config = appConfigs.first, let splitPlan = splitPlans.first {
                MainTabView(appConfig: config, splitPlan: splitPlan)
            } else {
                SetupFlowView()
            }
        }
    }
}

private struct MainTabView: View {
    var appConfig: AppConfig
    var splitPlan: SplitPlan

    var body: some View {
        TabView {
            NavigationStack {
                WorkoutDayView(appConfig: appConfig, splitPlan: splitPlan)
            }
            .tabItem {
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
            }

            NavigationStack {
                HistoryView(splitPlan: splitPlan)
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView(appConfig: appConfig, splitPlan: splitPlan)
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
            SplitPlan.self,
            PlanWeek.self,
            DayPlan.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            SessionEntry.self,
            LoggedSet.self,
            PlateOption.self,
            PlateCount.self
        ], inMemory: true)
}
