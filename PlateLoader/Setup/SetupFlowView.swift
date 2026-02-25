import SwiftData
import SwiftUI

struct SetupFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var step: Int = 0
    @State private var dayCardDrafts: [DayCardDraft] = []
    @State private var newDayName: String = ""

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
                        workoutDaysStep
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
            .onChange(of: barWeightUnit) { oldValue, newValue in
                guard oldValue != newValue else { return }
                barWeightValueText = newValue == .lb ? "45" : "20"
                plateDrafts = PlateDraft.defaults(for: newValue)
            }
        }
    }

    private var setupHeader: some View {
        VStack(spacing: 8) {
            Text("Step \(step + 1) of 2")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(step + 1), total: 2)
                .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private var workoutDaysStep: some View {
        Form {
            Section("Create Your Workout Days") {
                HStack {
                    TextField("Day name (e.g. Push, Legs)", text: $newDayName)
                        .textInputAutocapitalization(.words)
                    Button("Add") {
                        addDayCard()
                    }
                    .disabled(newDayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if dayCardDrafts.isEmpty {
                    Text("Add at least one workout day to get started.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dayCardDrafts) { draft in
                        Text(draft.label)
                    }
                    .onDelete(perform: deleteDayCards)
                    .onMove(perform: moveDayCards)
                }
            }

            Section {
                Text("Name your workout days however you like — Push/Pull/Legs, Upper/Lower, or by muscle group.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .environment(\.editMode, .constant(.active))
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

            Button(step == 1 ? "Finish" : "Next") {
                advance()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func addDayCard() {
        let trimmed = newDayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if dayCardDrafts.contains(where: {
            $0.label.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            errorMessage = "A workout day with that name already exists."
            return
        }

        dayCardDrafts.append(DayCardDraft(label: trimmed))
        newDayName = ""
    }

    private func deleteDayCards(at offsets: IndexSet) {
        dayCardDrafts.remove(atOffsets: offsets)
    }

    private func moveDayCards(from source: IndexSet, to destination: Int) {
        dayCardDrafts.move(fromOffsets: source, toOffset: destination)
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
            guard !dayCardDrafts.isEmpty else {
                errorMessage = "Add at least one workout day."
                return
            }
            step = 1
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
                barWeightValue: barWeight,
                barWeightUnit: barWeightUnit,
                plateCatalog: plateDrafts.map {
                    PlateOption(value: $0.value, unit: $0.unit, label: $0.label)
                }
            )

            for (index, draft) in dayCardDrafts.enumerated() {
                let workoutDay = WorkoutDay(label: draft.label, sortIndex: index)
                config.workoutDays.append(workoutDay)
            }

            modelContext.insert(config)
            try modelContext.save()
        } catch {
            errorMessage = "Could not finish setup: \(error.localizedDescription)"
        }
    }

    private func clearExistingDataIfNeeded() throws {
        let existingConfigs = try modelContext.fetch(FetchDescriptor<AppConfig>())
        let existingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())

        if !existingConfigs.isEmpty || !existingSessions.isEmpty {
            for config in existingConfigs {
                modelContext.delete(config)
            }
            for session in existingSessions {
                modelContext.delete(session)
            }
        }
    }
}

private struct DayCardDraft: Identifiable {
    let id = UUID()
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
