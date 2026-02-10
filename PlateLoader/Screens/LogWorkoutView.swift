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
    @State private var didLoadPreviousValues = false

    init(workout: WorkoutTemplate, dayPlan: DayPlan, weekIndex: Int, appConfig: AppConfig) {
        self.workout = workout
        self.dayPlan = dayPlan
        self.weekIndex = weekIndex
        self.appConfig = appConfig

        let plateIDs = appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .map(\.id)
        _setDrafts = State(initialValue: [SetDraft.makeDefault(plateOptionIDs: plateIDs)])
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

            if !workout.weightType.usesPlatePicker {
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
                    if workout.weightType.usesPlatePicker {
                        platePickerSetRow(index: index)
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
        .onAppear {
            loadMostRecentEntryIfAvailable()
        }
    }

    private var filteredPlateOptions: [PlateOption] {
        appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .sorted { $0.value > $1.value }
    }

    private var basePlateWeight: Double {
        workout.weightType == .barbell ? max(0, appConfig.barWeightValue) : 0
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
            }

            repsControl(for: index)
        }
        .padding(.vertical, 4)
    }

    private func platePickerSetRow(index: Int) -> some View {
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

            repsControl(for: index)
        }
        .padding(.vertical, 4)
    }

    private func repsControl(for setIndex: Int) -> some View {
        HStack {
            Text("Reps")
            Spacer()

            Button {
                updateReps(for: setIndex, delta: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(repsValue(for: setIndex) > 0 ? .primary : .tertiary)
            .disabled(repsValue(for: setIndex) == 0)

            Text("\(repsValue(for: setIndex))")
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .center)

            Button {
                updateReps(for: setIndex, delta: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    private func addSet() {
        let plateIDs = filteredPlateOptions.map(\.id)
        setDrafts.append(SetDraft.makeDefault(plateOptionIDs: plateIDs))
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
        return basePlateWeight + (2 * perSide)
    }

    private func repsValue(for setIndex: Int) -> Int {
        max(0, Int(setDrafts[setIndex].repsText) ?? 0)
    }

    private func updateReps(for setIndex: Int, delta: Int) {
        let next = max(0, repsValue(for: setIndex) + delta)
        setDrafts[setIndex].repsText = "\(next)"
    }

    private func loadMostRecentEntryIfAvailable() {
        guard !didLoadPreviousValues else { return }
        didLoadPreviousValues = true

        do {
            let descriptor = FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
            )
            let sessions = try modelContext.fetch(descriptor)

            let normalizedName = workout.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard let previousEntry = sessions.lazy.compactMap({ session in
                if let exact = session.entries.first(where: { $0.workoutTemplateId == workout.id }) {
                    return exact
                }

                return session.entries.first(where: { entry in
                    let entryName = entry.workoutNameSnapshot
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    return entry.weightTypeSnapshot == workout.weightType && entryName == normalizedName
                })
            }).first else {
                return
            }

            let sortedSets = previousEntry.sets.sorted { $0.setNumber < $1.setNumber }
            guard !sortedSets.isEmpty else { return }

            let plateOptionIDs = filteredPlateOptions.map(\.id)
            let defaultCounts = Dictionary(uniqueKeysWithValues: plateOptionIDs.map { ($0, 0) })

            if workout.weightType.usesPlatePicker {
                let restored: [SetDraft] = sortedSets.map { set in
                    var counts = defaultCounts
                    for plate in set.perSidePlates {
                        guard counts[plate.plateOptionId] != nil else { continue }
                        counts[plate.plateOptionId] = max(0, plate.countPerSide)
                    }

                    return SetDraft(
                        repsText: "\(max(0, set.reps))",
                        loadText: "",
                        plateCounts: counts
                    )
                }
                setDrafts = restored
                return
            }

            if let savedUnit = sortedSets.compactMap(\.loadUnit).first {
                currentUnit = savedUnit
            }

            let restored: [SetDraft] = sortedSets.map { set in
                let loadText = set.loadValue.map { max(0, $0).prettyWeight } ?? ""
                return SetDraft(
                    repsText: "\(max(0, set.reps))",
                    loadText: loadText,
                    plateCounts: defaultCounts
                )
            }
            setDrafts = restored
        } catch {
            print("Failed to load previous workout values: \(error)")
        }
    }

    private func saveSession() {
        guard !setDrafts.isEmpty else {
            errorMessage = "Add at least one set before saving."
            return
        }

        let loggedSets: [LoggedSet] = setDrafts.enumerated().map { index, draft in
            let reps = max(0, Int(draft.repsText) ?? 0)

            if workout.weightType.usesPlatePicker {
                let plateCounts: [PlateCount] = filteredPlateOptions.compactMap { option in
                    let count = max(0, draft.plateCounts[option.id] ?? 0)
                    guard count > 0 else { return nil }
                    return PlateCount(plateOptionId: option.id, countPerSide: count)
                }

                return LoggedSet(
                    setNumber: index + 1,
                    reps: reps,
                    perSidePlates: plateCounts,
                    barWeightValueSnapshot: basePlateWeight,
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

        if !workout.weightType.usesPlatePicker {
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

    static func makeDefault(plateOptionIDs: [UUID]) -> SetDraft {
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
