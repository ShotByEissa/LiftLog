import SwiftData
import SwiftUI

struct HistoryView: View {
    var splitPlan: SplitPlan

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var selectedWeekIndex: Int = 1
    @State private var selectedWeekday: Weekday = .sunday

    var body: some View {
        VStack(spacing: 12) {
            filters

            if filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "clock.badge.xmark",
                    description: Text("Log a workout and it will appear here.")
                )
            } else {
                List {
                    ForEach(filteredSessions, id: \.id) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text(sessionSubtitle(for: session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("History")
        .onAppear {
            ensureValidDaySelection()
        }
        .onChange(of: selectedWeekIndex) { _, _ in
            ensureValidDaySelection()
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("Week", selection: $selectedWeekIndex) {
                ForEach(splitPlan.sortedWeeks.map(\.weekIndex), id: \.self) { week in
                    Text("Week \(week)").tag(week)
                }
            }
            .pickerStyle(.segmented)

            if !availableDayPlans.isEmpty {
                Picker("Day", selection: $selectedWeekday) {
                    ForEach(availableDayPlans, id: \.weekday.rawValue) { dayPlan in
                        Text(dayPlan.weekday.shortName).tag(dayPlan.weekday)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var availableDayPlans: [DayPlan] {
        splitPlan.week(for: selectedWeekIndex)?.sortedDayPlans ?? []
    }

    private var filteredSessions: [WorkoutSession] {
        sessions.filter { session in
            session.weekIndex == selectedWeekIndex && session.weekday == selectedWeekday
        }
    }

    private func ensureValidDaySelection() {
        if selectedWeekIndex == 0 {
            selectedWeekIndex = splitPlan.sortedWeeks.first?.weekIndex ?? 1
        }

        guard let firstDay = availableDayPlans.first else { return }
        if !availableDayPlans.contains(where: { $0.weekday == selectedWeekday }) {
            selectedWeekday = firstDay.weekday
        }
    }

    private func sessionSubtitle(for session: WorkoutSession) -> String {
        let workoutCount = max(0, session.entries.count)
        let noun = workoutCount == 1 ? "workout" : "workouts"
        return "\(session.dayLabelSnapshot) • \(workoutCount) \(noun)"
    }
}
