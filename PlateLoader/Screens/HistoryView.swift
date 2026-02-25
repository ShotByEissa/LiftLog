import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var selectedLabel: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            if !uniqueLabels.isEmpty {
                labelFilter
            }

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
    }

    private var uniqueLabels: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions {
            let label = session.dayLabelSnapshot
            if !seen.contains(label) {
                seen.insert(label)
                result.append(label)
            }
        }
        return result.sorted()
    }

    private var labelFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: selectedLabel == nil) {
                    selectedLabel = nil
                }

                ForEach(uniqueLabels, id: \.self) { label in
                    filterChip(label: label, isSelected: selectedLabel == label) {
                        selectedLabel = label
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var filteredSessions: [WorkoutSession] {
        guard let label = selectedLabel else {
            return Array(sessions)
        }
        return sessions.filter { $0.dayLabelSnapshot == label }
    }

    private func sessionSubtitle(for session: WorkoutSession) -> String {
        let workoutCount = max(0, session.entries.count)
        let noun = workoutCount == 1 ? "workout" : "workouts"
        return "\(session.dayLabelSnapshot) • \(workoutCount) \(noun)"
    }
}
