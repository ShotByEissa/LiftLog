import SwiftData
import SwiftUI

struct SessionDetailView: View {
    var session: WorkoutSession

    @Query(sort: \AppConfig.createdAt)
    private var configs: [AppConfig]

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Date", value: session.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Week", value: "\(session.weekIndex)")
                LabeledContent("Day", value: session.weekday.fullName)
                LabeledContent("Label", value: session.dayLabelSnapshot)
            }

            ForEach(session.entries.indices, id: \.self) { entryIndex in
                let entry = session.entries[entryIndex]
                Section(entryTitle(for: entry, at: entryIndex)) {
                    ForEach(entry.sets.sorted(by: { $0.setNumber < $1.setNumber }), id: \.setNumber) { set in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set \(set.setNumber)")
                                .font(.headline)

                            if let setType = set.setType {
                                Text("Type: \(setType.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if entry.weightTypeSnapshot.usesPlatePicker {
                                if let total = set.computedTotalValue, let unit = set.computedTotalUnit {
                                    Text("Total: \(total.prettyWeight) \(unit.rawValue)")
                                }
                                Text("Reps: \(max(0, set.reps))")
                                if !set.perSidePlates.isEmpty {
                                    Text("Per side: \(plateBreakdown(for: set))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                let load = max(0, set.loadValue ?? 0)
                                let unitText = set.loadUnit?.rawValue ?? ""
                                Text("Weight: \(load.prettyWeight) \(unitText)")
                                Text("Reps: \(max(0, set.reps))")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Session Detail")
    }

    private func entryTitle(for entry: SessionEntry, at index: Int) -> String {
        let matchingTotal = session.entries.filter { sameWorkout($0, entry) }.count
        guard matchingTotal > 1 else { return entry.workoutNameSnapshot }

        let priorMatches = session.entries[..<index].filter { sameWorkout($0, entry) }.count
        return "\(entry.workoutNameSnapshot) #\(priorMatches + 1)"
    }

    private func sameWorkout(_ lhs: SessionEntry, _ rhs: SessionEntry) -> Bool {
        if lhs.workoutTemplateId == rhs.workoutTemplateId {
            return true
        }

        let lhsName = lhs.workoutNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhsName = rhs.workoutNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lhs.weightTypeSnapshot == rhs.weightTypeSnapshot && lhsName == rhsName
    }

    private func plateBreakdown(for loggedSet: LoggedSet) -> String {
        let labelsByID: [UUID: String] = Dictionary(
            uniqueKeysWithValues: (configs.first?.plateCatalog ?? []).map { ($0.id, $0.label) }
        )

        return loggedSet.perSidePlates
            .sorted(by: { $0.countPerSide > $1.countPerSide })
            .map { plate in
                let fallback = String(plate.plateOptionId.uuidString.prefix(6)) + "..."
                let label = labelsByID[plate.plateOptionId] ?? fallback
                return "\(label) x\(max(0, plate.countPerSide))"
            }
            .joined(separator: ", ")
    }
}
