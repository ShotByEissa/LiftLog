import SwiftData
import SwiftUI

struct AddWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutTemplate.name)
    private var allTemplates: [WorkoutTemplate]

    var dayPlan: DayPlan
    var defaultUnit: WeightUnit = .lb

    @State private var name: String = ""
    @State private var weightType: WeightType = .dumbbell
    @State private var preferredUnit: WeightUnit = .lb
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if !savedWorkouts.isEmpty {
                Section("Saved Workouts") {
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
                    }
                }
            }

            Section("Workout") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Weight Type", selection: $weightType) {
                    ForEach(WeightType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                if !weightType.usesPlatePicker {
                    Picker("Preferred Unit", selection: $preferredUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .navigationTitle("Add Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveWorkout()
                }
            }
        }
        .onAppear {
            preferredUnit = defaultUnit
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

        if dayPlan.activeSortedWorkouts.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cleanedName) == .orderedSame
                && $0.weightType == weightType
        }) {
            errorMessage = "That workout already exists for this day."
            return
        }

        let nextSortIndex = dayPlan.activeSortedWorkouts.count
        let unitToStore = weightType.usesPlatePicker ? defaultUnit : preferredUnit

        let newWorkout = WorkoutTemplate(
            name: cleanedName,
            weightType: weightType,
            preferredUnit: unitToStore,
            sortIndex: nextSortIndex,
            isArchived: false
        )

        dayPlan.workouts.append(newWorkout)

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
                    template.preferredUnit.rawValue
                ].joined(separator: "|")

                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
    }

    private func savedWorkoutSubtitle(for template: WorkoutTemplate) -> String {
        if template.weightType.usesPlatePicker {
            return template.weightType.title
        }
        return "\(template.weightType.title) • \(template.preferredUnit.title)"
    }

    private func apply(template: WorkoutTemplate) {
        name = template.name
        weightType = template.weightType
        preferredUnit = template.preferredUnit
    }
}
