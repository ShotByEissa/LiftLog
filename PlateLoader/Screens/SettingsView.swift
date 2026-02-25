import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("profileFirstName") private var profileFirstName: String = ""

    var appConfig: AppConfig

    @State private var barWeightUnitDraft: WeightUnit
    @State private var barWeightValueText: String
    @State private var plateDrafts: [EditablePlate]
    @State private var customPlateText: String = ""

    @State private var errorMessage: String?
    @State private var showFactoryResetConfirm = false

    @State private var dayToRename: WorkoutDay?
    @State private var renameValue: String = ""
    @State private var showAddDay = false
    @State private var newDayName: String = ""

    init(appConfig: AppConfig) {
        self.appConfig = appConfig

        _barWeightUnitDraft = State(initialValue: appConfig.barWeightUnit)
        _barWeightValueText = State(initialValue: appConfig.barWeightValue.prettyWeight)

        let initialPlates = appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .sorted { $0.value > $1.value }
            .map { EditablePlate(id: $0.id, value: $0.value, unit: $0.unit, label: $0.label) }

        _plateDrafts = State(initialValue: initialPlates.isEmpty ? EditablePlate.defaults(for: appConfig.barWeightUnit) : initialPlates)
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("First name", text: $profileFirstName)
                    .textInputAutocapitalization(.words)
            }

            Section("Workout Days") {
                ForEach(appConfig.sortedWorkoutDays, id: \.id) { day in
                    HStack {
                        Text(day.label)
                        Spacer()
                        Text("\(day.activeSortedWorkouts.count) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Rename") {
                            dayToRename = day
                            renameValue = day.label
                        }

                        Button("Delete", role: .destructive) {
                            deleteWorkoutDay(day)
                        }
                    }
                }
                .onMove(perform: moveWorkoutDays)

                Button("Add Workout Day") {
                    showAddDay = true
                }
            }

            Section("Barbell Defaults") {
                Picker("Unit", selection: $barWeightUnitDraft) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Bar weight", text: $barWeightValueText)
                    .keyboardType(.decimalPad)
            }

            Section("Plate Catalog") {
                ForEach(plateDrafts) { plate in
                    HStack {
                        Text(plate.label)
                        Spacer()
                        Text("\(plate.value.prettyWeight) \(plate.unit.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deletePlateDrafts)

                HStack {
                    TextField("Custom plate value", text: $customPlateText)
                        .keyboardType(.decimalPad)
                    Button("Add") {
                        addPlateDraft()
                    }
                }
            }

            Section {
                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)

                Button("Factory Reset", role: .destructive) {
                    showFactoryResetConfirm = true
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Factory Reset?", isPresented: $showFactoryResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                factoryReset()
            }
        } message: {
            Text("This clears all setup, workouts, and history from local storage.")
        }
        .alert("Add Workout Day", isPresented: $showAddDay) {
            TextField("Day name", text: $newDayName)
            Button("Cancel", role: .cancel) {
                newDayName = ""
            }
            Button("Add") {
                addWorkoutDay()
            }
        } message: {
            Text("Give your workout day a name.")
        }
        .alert("Rename Workout Day", isPresented: Binding(
            get: { dayToRename != nil },
            set: { isPresented in
                if !isPresented {
                    dayToRename = nil
                    renameValue = ""
                }
            }
        )) {
            TextField("Day name", text: $renameValue)
            Button("Cancel", role: .cancel) {
                dayToRename = nil
                renameValue = ""
            }
            Button("Save") {
                saveRenameDay()
            }
        }
        .onChange(of: barWeightUnitDraft) { oldValue, newValue in
            guard oldValue != newValue else { return }
            let matching = appConfig.plateCatalog
                .filter { $0.unit == newValue }
                .sorted { $0.value > $1.value }
                .map { EditablePlate(id: $0.id, value: $0.value, unit: $0.unit, label: $0.label) }
            plateDrafts = matching.isEmpty ? EditablePlate.defaults(for: newValue) : matching
            if barWeightValueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                barWeightValueText = newValue == .lb ? "45" : "20"
            }
        }
    }

    private func moveWorkoutDays(from source: IndexSet, to destination: Int) {
        var days = appConfig.sortedWorkoutDays
        days.move(fromOffsets: source, toOffset: destination)
        for (index, day) in days.enumerated() {
            day.sortIndex = index
        }
        save()
    }

    private func deleteWorkoutDay(_ day: WorkoutDay) {
        appConfig.workoutDays.removeAll { $0.id == day.id }
        modelContext.delete(day)
        for (index, d) in appConfig.sortedWorkoutDays.enumerated() {
            d.sortIndex = index
        }
        save()
    }

    private func addWorkoutDay() {
        let trimmed = newDayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newDayName = ""
            return
        }

        if appConfig.workoutDays.contains(where: {
            $0.label.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            errorMessage = "A workout day with that name already exists."
            newDayName = ""
            return
        }

        let nextIndex = appConfig.workoutDays.count
        let day = WorkoutDay(label: trimmed, sortIndex: nextIndex)
        appConfig.workoutDays.append(day)
        newDayName = ""
        save()
    }

    private func saveRenameDay() {
        guard let day = dayToRename else { return }
        let trimmed = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            day.label = trimmed
            save()
        }
        dayToRename = nil
        renameValue = ""
    }

    private func deletePlateDrafts(at offsets: IndexSet) {
        plateDrafts.remove(atOffsets: offsets)
    }

    private func addPlateDraft() {
        let trimmed = customPlateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value >= 0 else {
            errorMessage = "Plate value must be a number >= 0."
            return
        }

        if plateDrafts.contains(where: { abs($0.value - value) < 0.0001 }) {
            customPlateText = ""
            return
        }

        let draft = EditablePlate(
            id: UUID(),
            value: value,
            unit: barWeightUnitDraft,
            label: "\(value.prettyWeight) \(barWeightUnitDraft.rawValue)"
        )
        plateDrafts.append(draft)
        plateDrafts.sort { $0.value > $1.value }
        customPlateText = ""
    }

    private func saveChanges() {
        guard let barWeight = Double(barWeightValueText), barWeight >= 0 else {
            errorMessage = "Bar weight must be a number >= 0."
            return
        }

        guard !plateDrafts.isEmpty else {
            errorMessage = "Add at least one plate option."
            return
        }

        appConfig.barWeightUnit = barWeightUnitDraft
        appConfig.barWeightValue = barWeight

        rewritePlateCatalog()

        save()
    }

    private func rewritePlateCatalog() {
        let existing = appConfig.plateCatalog
        appConfig.plateCatalog.removeAll()

        for option in existing {
            modelContext.delete(option)
        }

        for plate in plateDrafts {
            appConfig.plateCatalog.append(
                PlateOption(id: plate.id, value: plate.value, unit: barWeightUnitDraft, label: plate.label)
            )
        }
    }

    private func factoryReset() {
        do {
            let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            let configs = try modelContext.fetch(FetchDescriptor<AppConfig>())

            for config in configs {
                modelContext.delete(config)
            }
            for session in sessions {
                modelContext.delete(session)
            }

            try modelContext.save()
        } catch {
            errorMessage = "Factory reset failed: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Could not save settings: \(error.localizedDescription)"
        }
    }
}

private struct EditablePlate: Identifiable {
    var id: UUID
    var value: Double
    var unit: WeightUnit
    var label: String

    static func defaults(for unit: WeightUnit) -> [EditablePlate] {
        PlatePresets.defaultValues(for: unit).map {
            EditablePlate(id: UUID(), value: $0, unit: unit, label: "\($0.prettyWeight) \(unit.rawValue)")
        }
    }
}
