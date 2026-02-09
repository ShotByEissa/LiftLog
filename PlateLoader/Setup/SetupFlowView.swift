import SwiftData
import SwiftUI

struct SetupFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var step: Int = 0
    @State private var splitLengthWeeks: Int = 1
    @State private var selectedWeekEditor: Int = 1
    @State private var weekDrafts: [SetupWeekDraft] = [SetupWeekDraft.makeDefault(weekIndex: 1)]

    @State private var barWeightUnit: WeightUnit = .lb
    @State private var barWeightValueText: String = "45"
    @State private var plateDrafts: [PlateDraft] = PlateDraft.defaults(for: .lb)
    @State private var customPlateValueText: String = ""

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                setupHeader
                Divider()

                Group {
                    switch step {
                    case 0:
                        splitLengthStep
                    case 1:
                        splitPlanStep
                    default:
                        barbellDefaultsStep
                    }
                }

                Divider()
                footerControls
            }
            .navigationTitle("PlateLoader Setup")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Setup Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown setup error.")
            }
            .onChange(of: splitLengthWeeks) { _, newValue in
                syncWeeks(to: newValue)
            }
            .onChange(of: barWeightUnit) { oldValue, newValue in
                guard oldValue != newValue else { return }
                barWeightValueText = newValue == .lb ? "45" : "20"
                plateDrafts = PlateDraft.defaults(for: newValue)
            }
        }
    }

    private var setupHeader: some View {
        VStack(spacing: 8) {
            Text("Step \(step + 1) of 3")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(step + 1), total: 3)
                .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private var splitLengthStep: some View {
        Form {
            Section("Split Length") {
                Picker("Weeks", selection: $splitLengthWeeks) {
                    ForEach(1...4, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("\(splitLengthWeeks) week split", value: $splitLengthWeeks, in: 1...4)
            }

            Section {
                Text("Choose how many weeks are in your repeating plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var splitPlanStep: some View {
        Form {
            Section("Week") {
                Picker("Editing", selection: $selectedWeekEditor) {
                    ForEach(1...splitLengthWeeks, id: \.self) { weekIndex in
                        Text("Week \(weekIndex)").tag(weekIndex)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let weekIndex = weekDrafts.firstIndex(where: { $0.weekIndex == selectedWeekEditor }) {
                Section("Workout Days") {
                    ForEach(weekDrafts[weekIndex].days.indices, id: \.self) { dayIndex in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(
                                weekDrafts[weekIndex].days[dayIndex].weekday.fullName,
                                isOn: Binding(
                                    get: { weekDrafts[weekIndex].days[dayIndex].isSelected },
                                    set: { isSelected in
                                        weekDrafts[weekIndex].days[dayIndex].isSelected = isSelected
                                        if !isSelected {
                                            weekDrafts[weekIndex].days[dayIndex].label = ""
                                        }
                                    }
                                )
                            )

                            if weekDrafts[weekIndex].days[dayIndex].isSelected {
                                TextField(
                                    "Label (e.g. Chest)",
                                    text: Binding(
                                        get: { weekDrafts[weekIndex].days[dayIndex].label },
                                        set: { weekDrafts[weekIndex].days[dayIndex].label = $0 }
                                    )
                                )
                                .textInputAutocapitalization(.words)
                            }
                        }
                    }
                }
            }
        }
    }

    private var barbellDefaultsStep: some View {
        Form {
            Section("Bar Weight") {
                Picker("Unit", selection: $barWeightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Bar weight", text: $barWeightValueText)
                    .keyboardType(.decimalPad)
            }

            Section("Plate Catalog") {
                if plateDrafts.isEmpty {
                    Text("No plates added yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(plateDrafts) { plate in
                    HStack {
                        Text(plate.label)
                        Spacer()
                        Text("\(plate.value.prettyWeight) \(plate.unit.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deletePlates)

                HStack {
                    TextField("Custom plate value", text: $customPlateValueText)
                        .keyboardType(.decimalPad)
                    Button("Add") {
                        addCustomPlate()
                    }
                }
            }

            Section {
                Text("Defaults loaded: lb [45,35,25,10,5,2.5], kg [25,20,15,10,5,2.5,1.25].")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footerControls: some View {
        HStack {
            if step > 0 {
                Button("Back") {
                    step -= 1
                }
            }

            Spacer()

            Button(step == 2 ? "Finish" : "Next") {
                advance()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func syncWeeks(to requestedLength: Int) {
        let targetLength = AppConfig.clampSplitLength(requestedLength)
        splitLengthWeeks = targetLength

        if weekDrafts.count > targetLength {
            weekDrafts = Array(weekDrafts.prefix(targetLength))
        } else if weekDrafts.count < targetLength {
            let start = weekDrafts.count + 1
            for index in start...targetLength {
                weekDrafts.append(SetupWeekDraft.makeDefault(weekIndex: index))
            }
        }

        if selectedWeekEditor > targetLength {
            selectedWeekEditor = targetLength
        }
    }

    private func deletePlates(at offsets: IndexSet) {
        plateDrafts.remove(atOffsets: offsets)
    }

    private func addCustomPlate() {
        let trimmed = customPlateValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value >= 0 else {
            errorMessage = "Custom plate must be a number >= 0."
            return
        }

        let draft = PlateDraft(
            value: value,
            unit: barWeightUnit,
            label: "\(value.prettyWeight) \(barWeightUnit.rawValue)"
        )

        if !plateDrafts.contains(where: { abs($0.value - value) < 0.0001 }) {
            plateDrafts.append(draft)
            plateDrafts.sort { $0.value > $1.value }
        }

        customPlateValueText = ""
    }

    private func advance() {
        if step == 0 {
            step = 1
            return
        }

        if step == 1 {
            for weekDraft in weekDrafts.prefix(splitLengthWeeks) {
                let selectedDays = weekDraft.days.filter(\.isSelected)
                if selectedDays.isEmpty {
                    errorMessage = "Each week must have at least one selected workout day."
                    return
                }
            }
            step = 2
            return
        }

        completeSetup()
    }

    private func completeSetup() {
        guard let barWeight = Double(barWeightValueText), barWeight >= 0 else {
            errorMessage = "Bar weight must be a number >= 0."
            return
        }

        guard !plateDrafts.isEmpty else {
            errorMessage = "Add at least one plate option."
            return
        }

        do {
            try clearExistingDataIfNeeded()

            let config = AppConfig(
                splitLengthWeeks: splitLengthWeeks,
                barWeightValue: barWeight,
                barWeightUnit: barWeightUnit,
                plateCatalog: plateDrafts.map {
                    PlateOption(value: $0.value, unit: $0.unit, label: $0.label)
                }
            )

            let splitPlan = SplitPlan()
            for weekIndex in 1...splitLengthWeeks {
                guard let weekDraft = weekDrafts.first(where: { $0.weekIndex == weekIndex }) else { continue }

                let planWeek = PlanWeek(weekIndex: weekIndex)
                for day in weekDraft.days where day.isSelected {
                    let cleanedLabel = day.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalLabel = cleanedLabel.isEmpty ? day.weekday.fullName : cleanedLabel
                    let dayPlan = DayPlan(weekday: day.weekday, label: finalLabel)
                    planWeek.dayPlans.append(dayPlan)
                }
                splitPlan.weeks.append(planWeek)
            }

            modelContext.insert(config)
            modelContext.insert(splitPlan)
            try modelContext.save()
        } catch {
            errorMessage = "Could not finish setup: \(error.localizedDescription)"
        }
    }

    private func clearExistingDataIfNeeded() throws {
        let existingConfigs = try modelContext.fetch(FetchDescriptor<AppConfig>())
        let existingSplitPlans = try modelContext.fetch(FetchDescriptor<SplitPlan>())
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())

        if !existingConfigs.isEmpty || !existingSplitPlans.isEmpty || !existingSessions.isEmpty {
            for config in existingConfigs {
                modelContext.delete(config)
            }
            for plan in existingSplitPlans {
                modelContext.delete(plan)
            }
            for session in existingSessions {
                modelContext.delete(session)
            }
        }
    }
}

private struct SetupWeekDraft: Identifiable {
    let id = UUID()
    var weekIndex: Int
    var days: [SetupDayDraft]

    static func makeDefault(weekIndex: Int) -> SetupWeekDraft {
        SetupWeekDraft(
            weekIndex: weekIndex,
            days: Weekday.allCases.map { day in
                SetupDayDraft(weekday: day, isSelected: false, label: "")
            }
        )
    }
}

private struct SetupDayDraft: Identifiable {
    let id = UUID()
    var weekday: Weekday
    var isSelected: Bool
    var label: String
}

private struct PlateDraft: Identifiable {
    let id = UUID()
    var value: Double
    var unit: WeightUnit
    var label: String

    static func defaults(for unit: WeightUnit) -> [PlateDraft] {
        PlatePresets.defaultValues(for: unit).map {
            PlateDraft(value: $0, unit: unit, label: "\($0.prettyWeight) \(unit.rawValue)")
        }
    }
}
