import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("profileFirstName") private var profileFirstName: String = ""

    var appConfig: AppConfig
    var splitPlan: SplitPlan

    @State private var splitLengthWeeksDraft: Int
    @State private var weekDrafts: [WeekEditDraft]

    @State private var barWeightUnitDraft: WeightUnit
    @State private var barWeightValueText: String
    @State private var plateDrafts: [EditablePlate]
    @State private var customPlateText: String = ""

    @State private var errorMessage: String?
    @State private var showFactoryResetConfirm = false
    @State private var didHydrateWeekDrafts = false

    init(appConfig: AppConfig, splitPlan: SplitPlan) {
        self.appConfig = appConfig
        self.splitPlan = splitPlan

        _splitLengthWeeksDraft = State(initialValue: appConfig.splitLengthWeeks)
        _weekDrafts = State(initialValue: WeekEditDraft.defaults(splitLength: appConfig.splitLengthWeeks))

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

            Section("Split Length") {
                Stepper("\(splitLengthWeeksDraft) week split", value: $splitLengthWeeksDraft, in: 1...4)
            }

            ForEach(1...splitLengthWeeksDraft, id: \.self) { weekIndex in
                if let draftIndex = weekDrafts.firstIndex(where: { $0.weekIndex == weekIndex }) {
                    Section("Week \(weekIndex)") {
                        ForEach(weekDrafts[draftIndex].days.indices, id: \.self) { dayIndex in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(
                                    weekDrafts[draftIndex].days[dayIndex].weekday.fullName,
                                    isOn: Binding(
                                        get: { weekDrafts[draftIndex].days[dayIndex].isSelected },
                                        set: { isSelected in
                                            weekDrafts[draftIndex].days[dayIndex].isSelected = isSelected
                                            if !isSelected {
                                                weekDrafts[draftIndex].days[dayIndex].label = ""
                                            }
                                        }
                                    )
                                )

                                if weekDrafts[draftIndex].days[dayIndex].isSelected {
                                    TextField(
                                        "Label",
                                        text: Binding(
                                            get: { weekDrafts[draftIndex].days[dayIndex].label },
                                            set: { weekDrafts[draftIndex].days[dayIndex].label = $0 }
                                        )
                                    )
                                    .textInputAutocapitalization(.words)
                                }
                            }
                        }
                    }
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
        .onChange(of: splitLengthWeeksDraft) { _, newValue in
            syncWeekDrafts(to: newValue)
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
        .onAppear {
            hydrateWeekDraftsIfNeeded()
        }
    }

    private func syncWeekDrafts(to requestedLength: Int) {
        let target = AppConfig.clampSplitLength(requestedLength)
        splitLengthWeeksDraft = target

        if weekDrafts.count > target {
            weekDrafts = Array(weekDrafts.prefix(target))
        } else if weekDrafts.count < target {
            let start = weekDrafts.count + 1
            for index in start...target {
                weekDrafts.append(WeekEditDraft.makeDefault(weekIndex: index))
            }
        }
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

    private func hydrateWeekDraftsIfNeeded() {
        guard !didHydrateWeekDrafts else { return }
        didHydrateWeekDrafts = true

        do {
            let fetchedPlans = try modelContext.fetch(FetchDescriptor<SplitPlan>())
            guard let currentPlan = fetchedPlans.first else { return }
            weekDrafts = WeekEditDraft.from(splitPlan: currentPlan, splitLength: splitLengthWeeksDraft)
        } catch {
            // Keep defaults if hydration fails.
        }
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

        for weekDraft in weekDrafts.prefix(splitLengthWeeksDraft) {
            if weekDraft.days.filter(\.isSelected).isEmpty {
                errorMessage = "Each week must have at least one selected day."
                return
            }
        }

        appConfig.splitLengthWeeks = splitLengthWeeksDraft
        appConfig.barWeightUnit = barWeightUnitDraft
        appConfig.barWeightValue = barWeight

        rewritePlateCatalog()
        applySplitDraftsToPlan()

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Could not save settings: \(error.localizedDescription)"
        }
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

    private func applySplitDraftsToPlan() {
        // Remove any weeks outside the chosen split length.
        let weeksToRemove = splitPlan.weeks.filter { $0.weekIndex > splitLengthWeeksDraft }
        for week in weeksToRemove {
            splitPlan.weeks.removeAll(where: { $0.weekIndex == week.weekIndex })
            modelContext.delete(week)
        }

        for weekIndex in 1...splitLengthWeeksDraft {
            guard let draft = weekDrafts.first(where: { $0.weekIndex == weekIndex }) else { continue }

            let week = splitPlan.week(for: weekIndex) ?? {
                let newWeek = PlanWeek(weekIndex: weekIndex)
                splitPlan.weeks.append(newWeek)
                return newWeek
            }()

            let selectedDays = draft.days.filter(\.isSelected)

            let daysToRemove = week.dayPlans.filter { existingDay in
                !selectedDays.contains(where: { $0.weekday == existingDay.weekday })
            }
            for existingDay in daysToRemove {
                week.dayPlans.removeAll(where: { $0.weekday == existingDay.weekday })
                modelContext.delete(existingDay)
            }

            for selected in selectedDays {
                let cleanLabel = selected.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalLabel = cleanLabel.isEmpty ? selected.weekday.fullName : cleanLabel

                if let existing = week.dayPlans.first(where: { $0.weekday == selected.weekday }) {
                    existing.label = finalLabel
                } else {
                    week.dayPlans.append(DayPlan(weekday: selected.weekday, label: finalLabel))
                }
            }
        }
    }

    private func factoryReset() {
        do {
            let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            let plans = try modelContext.fetch(FetchDescriptor<SplitPlan>())
            let configs = try modelContext.fetch(FetchDescriptor<AppConfig>())

            for config in configs {
                modelContext.delete(config)
            }
            for plan in plans {
                modelContext.delete(plan)
            }
            for session in sessions {
                modelContext.delete(session)
            }

            try modelContext.save()
        } catch {
            errorMessage = "Factory reset failed: \(error.localizedDescription)"
        }
    }
}

private struct WeekEditDraft: Identifiable {
    let id = UUID()
    var weekIndex: Int
    var days: [DayEditDraft]

    static func defaults(splitLength: Int) -> [WeekEditDraft] {
        (1...max(1, splitLength)).map { makeDefault(weekIndex: $0) }
    }

    static func makeDefault(weekIndex: Int) -> WeekEditDraft {
        WeekEditDraft(
            weekIndex: weekIndex,
            days: Weekday.allCases.map {
                DayEditDraft(weekday: $0, isSelected: false, label: "")
            }
        )
    }

    static func from(splitPlan: SplitPlan, splitLength: Int) -> [WeekEditDraft] {
        (1...splitLength).map { weekIndex in
            let existingWeek = splitPlan.week(for: weekIndex)
            let dayMap: [Weekday: DayPlan] = Dictionary(
                uniqueKeysWithValues: (existingWeek?.dayPlans ?? []).map { ($0.weekday, $0) }
            )

            return WeekEditDraft(
                weekIndex: weekIndex,
                days: Weekday.allCases.map { weekday in
                    if let dayPlan = dayMap[weekday] {
                        return DayEditDraft(weekday: weekday, isSelected: true, label: dayPlan.label)
                    }
                    return DayEditDraft(weekday: weekday, isSelected: false, label: "")
                }
            )
        }
    }
}

private struct DayEditDraft: Identifiable {
    let id = UUID()
    var weekday: Weekday
    var isSelected: Bool
    var label: String
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
