import SwiftData
import SwiftUI

struct AddWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutTemplate.name)
    private var allTemplates: [WorkoutTemplate]

    var dayPlan: DayPlan
    var defaultUnit: WeightUnit = .lb
    var workoutToEdit: WorkoutTemplate?

    @State private var name: String = ""
    @State private var weightType: WeightType = .dumbbell
    @State private var plannedWarmUpSetCount: Int = 1
    @State private var plannedWorkingSetCount: Int = 3
    @State private var preferredUnit: WeightUnit = .lb
    @State private var showSavedWorkouts = false
    @State private var errorMessage: String?

    init(dayPlan: DayPlan, defaultUnit: WeightUnit = .lb, workoutToEdit: WorkoutTemplate? = nil) {
        self.dayPlan = dayPlan
        self.defaultUnit = defaultUnit
        self.workoutToEdit = workoutToEdit

        _name = State(initialValue: workoutToEdit?.name ?? "")
        _weightType = State(initialValue: workoutToEdit?.weightType ?? .dumbbell)
        _plannedWarmUpSetCount = State(initialValue: max(0, workoutToEdit?.plannedWarmUpSetCount ?? 1))
        _plannedWorkingSetCount = State(initialValue: max(1, workoutToEdit?.plannedWorkingSetCount ?? 3))
        _preferredUnit = State(initialValue: workoutToEdit?.preferredUnit ?? defaultUnit)
    }

    private var isEditingPlan: Bool {
        workoutToEdit != nil
    }

    var body: some View {
        Form {
            if !savedWorkouts.isEmpty {
                Section {
                    DisclosureGroup("Saved Workouts", isExpanded: $showSavedWorkouts) {
                        ForEach(savedWorkouts, id: \.id) { template in
                            Button {
                                apply(template: template)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .foregroundStyle(.primary)
                                    Text(savedWorkoutSubtitle(for: template))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Plan Workout") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Weight Type", selection: $weightType) {
                    ForEach(WeightType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                Stepper(value: $plannedWarmUpSetCount, in: 0...10) {
                    HStack {
                        Text("Warm-Up Sets")
                        Spacer()
                        Text("\(plannedWarmUpSetCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $plannedWorkingSetCount, in: 1...12) {
                    HStack {
                        Text("Working Sets")
                        Spacer()
                        Text("\(plannedWorkingSetCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isEditingPlan ? "Edit Plan" : "Plan Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isEditingPlan ? "Update" : "Save") {
                    saveWorkout()
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

    private func saveWorkout() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            errorMessage = "Workout name is required."
            return
        }

        let editingID = workoutToEdit?.id
        if dayPlan.activeSortedWorkouts.contains(where: {
            $0.id != editingID &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cleanedName) == .orderedSame
                && $0.weightType == weightType
        }) {
            errorMessage = "That workout already exists for this day."
            return
        }

        if let existing = workoutToEdit {
            existing.name = cleanedName
            existing.weightType = weightType
            existing.plannedWarmUpSetCount = max(0, plannedWarmUpSetCount)
            existing.plannedWorkingSetCount = max(1, plannedWorkingSetCount)
            existing.preferredUnit = weightType.usesPlatePicker ? defaultUnit : preferredUnit
        } else {
            let nextSortIndex = dayPlan.activeSortedWorkouts.count
            let unitToStore = weightType.usesPlatePicker ? defaultUnit : preferredUnit
            let newWorkout = WorkoutTemplate(
                name: cleanedName,
                weightType: weightType,
                preferredUnit: unitToStore,
                plannedWarmUpSetCount: max(0, plannedWarmUpSetCount),
                plannedWorkingSetCount: max(1, plannedWorkingSetCount),
                sortIndex: nextSortIndex,
                isArchived: false
            )
            dayPlan.workouts.append(newWorkout)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var savedWorkouts: [WorkoutTemplate] {
        var seen = Set<String>()

        return allTemplates
            .filter { !$0.isArchived }
            .filter { template in
                let key = [
                    template.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    template.weightType.rawValue,
                    template.preferredUnit.rawValue,
                    "\(template.plannedWarmUpSetCount)",
                    "\(template.plannedWorkingSetCount)"
                ].joined(separator: "|")

                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
    }

    private func savedWorkoutSubtitle(for template: WorkoutTemplate) -> String {
        let warmUps = max(0, template.plannedWarmUpSetCount)
        let working = max(1, template.plannedWorkingSetCount)
        return "\(template.weightType.title) • WU \(warmUps) • WK \(working)"
    }

    private func apply(template: WorkoutTemplate) {
        name = template.name
        weightType = template.weightType
        plannedWarmUpSetCount = max(0, template.plannedWarmUpSetCount)
        plannedWorkingSetCount = max(1, template.plannedWorkingSetCount)
        preferredUnit = template.preferredUnit
    }
}
