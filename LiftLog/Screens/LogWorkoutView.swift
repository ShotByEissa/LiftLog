import SwiftData
import SwiftUI

struct LogWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var workout: WorkoutTemplate
    var dayPlan: DayPlan
    var weekIndex: Int
    var appConfig: AppConfig

    @State private var setDrafts: [SetDraft]
    @State private var currentUnit: WeightUnit
    @State private var sessionDate: Date = .now
    @State private var errorMessage: String?

    init(workout: WorkoutTemplate, dayPlan: DayPlan, weekIndex: Int, appConfig: AppConfig) {
        self.workout = workout
        self.dayPlan = dayPlan
        self.weekIndex = weekIndex
        self.appConfig = appConfig

        let plateIDs = appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .map(\.id)
        _setDrafts = State(initialValue: [SetDraft.makeDefault(for: workout.weightType, plateOptionIDs: plateIDs)])
        _currentUnit = State(initialValue: workout.preferredUnit)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.title2.bold())
                    Text("\(dayPlan.label) • \(sessionDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if workout.weightType != .barbell {
                Section("Unit") {
                    Picker("Unit", selection: $currentUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Sets") {
                ForEach(setDrafts.indices, id: \.self) { index in
                    if workout.weightType == .barbell {
                        barbellSetRow(index: index)
                    } else {
                        numericSetRow(index: index)
                    }
                }
                .onDelete(perform: deleteSets)

                Button("Add Set") {
                    addSet()
                }

                Button("Copy Last Set") {
                    copyLastSet()
                }
                .disabled(setDrafts.isEmpty)
            }
        }
        .navigationTitle("Log Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveSession()
                }
            }
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var filteredPlateOptions: [PlateOption] {
        appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .sorted { $0.value > $1.value }
    }

    private func numericSetRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set \(index + 1)")
                .font(.headline)

            HStack {
                TextField(
                    "Weight",
                    text: Binding(
                        get: { setDrafts[index].loadText },
                        set: { setDrafts[index].loadText = $0 }
                    )
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

                Text(currentUnit.title)
                    .foregroundStyle(.secondary)

                TextField(
                    "Reps",
                    text: Binding(
                        get: { setDrafts[index].repsText },
                        set: { setDrafts[index].repsText = $0 }
                    )
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }

    private func barbellSetRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set \(index + 1)")
                .font(.headline)

            if filteredPlateOptions.isEmpty {
                Text("No plates available for \(appConfig.barWeightUnit.title). Add them in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredPlateOptions, id: \.id) { plate in
                    Stepper(
                        "\(plate.label) per side: \(plateCount(for: index, plateID: plate.id))",
                        value: Binding(
                            get: { plateCount(for: index, plateID: plate.id) },
                            set: { newValue in
                                setPlateCount(max(0, newValue), for: index, plateID: plate.id)
                            }
                        ),
                        in: 0...20
                    )
                }

                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(totalForSet(index).prettyWeight) \(appConfig.barWeightUnit.rawValue)")
                        .font(.subheadline.bold())
                }
            }

            HStack {
                Text("Reps")
                TextField(
                    "0",
                    text: Binding(
                        get: { setDrafts[index].repsText },
                        set: { setDrafts[index].repsText = $0 }
                    )
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }

    private func addSet() {
        let plateIDs = filteredPlateOptions.map(\.id)
        setDrafts.append(SetDraft.makeDefault(for: workout.weightType, plateOptionIDs: plateIDs))
    }

    private func copyLastSet() {
        guard let last = setDrafts.last else { return }
        setDrafts.append(last.duplicate())
    }

    private func deleteSets(at offsets: IndexSet) {
        setDrafts.remove(atOffsets: offsets)
    }

    private func plateCount(for setIndex: Int, plateID: UUID) -> Int {
        setDrafts[setIndex].plateCounts[plateID] ?? 0
    }

    private func setPlateCount(_ count: Int, for setIndex: Int, plateID: UUID) {
        setDrafts[setIndex].plateCounts[plateID] = max(0, count)
    }

    private func totalForSet(_ index: Int) -> Double {
        let perSide = filteredPlateOptions.reduce(0.0) { partial, plate in
            let count = Double(plateCount(for: index, plateID: plate.id))
            return partial + (plate.value * count)
        }
        return max(0, appConfig.barWeightValue) + (2 * perSide)
    }

    private func saveSession() {
        guard !setDrafts.isEmpty else {
            errorMessage = "Add at least one set before saving."
            return
        }

        let loggedSets: [LoggedSet] = setDrafts.enumerated().map { index, draft in
            let reps = max(0, Int(draft.repsText) ?? 0)

            if workout.weightType == .barbell {
                let plateCounts: [PlateCount] = filteredPlateOptions.compactMap { option in
                    let count = max(0, draft.plateCounts[option.id] ?? 0)
                    guard count > 0 else { return nil }
                    return PlateCount(plateOptionId: option.id, countPerSide: count)
                }

                return LoggedSet(
                    setNumber: index + 1,
                    reps: reps,
                    perSidePlates: plateCounts,
                    barWeightValueSnapshot: max(0, appConfig.barWeightValue),
                    barWeightUnitSnapshot: appConfig.barWeightUnit,
                    computedTotalValue: totalForSet(index),
                    computedTotalUnit: appConfig.barWeightUnit
                )
            }

            let load = max(0, Double(draft.loadText) ?? 0)
            return LoggedSet(
                setNumber: index + 1,
                reps: reps,
                loadValue: load,
                loadUnit: currentUnit
            )
        }

        let entry = SessionEntry(
            workoutTemplateId: workout.id,
            workoutNameSnapshot: workout.name,
            weightTypeSnapshot: workout.weightType,
            sets: loggedSets
        )

        let session = WorkoutSession(
            date: sessionDate,
            weekIndex: weekIndex,
            weekday: dayPlan.weekday,
            dayLabelSnapshot: dayPlan.label,
            entries: [entry]
        )

        if workout.weightType != .barbell {
            workout.preferredUnit = currentUnit
        }

        modelContext.insert(session)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetDraft: Identifiable {
    let id = UUID()
    var repsText: String
    var loadText: String
    var plateCounts: [UUID: Int]

    static func makeDefault(for weightType: WeightType, plateOptionIDs: [UUID]) -> SetDraft {
        SetDraft(
            repsText: "",
            loadText: "",
            plateCounts: Dictionary(uniqueKeysWithValues: plateOptionIDs.map { ($0, 0) })
        )
    }

    func duplicate() -> SetDraft {
        SetDraft(repsText: repsText, loadText: loadText, plateCounts: plateCounts)
    }
}
