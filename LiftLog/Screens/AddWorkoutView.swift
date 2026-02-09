import SwiftData
import SwiftUI

struct AddWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var dayPlan: DayPlan
    var defaultUnit: WeightUnit = .lb

    @State private var name: String = ""
    @State private var weightType: WeightType = .dumbbell
    @State private var preferredUnit: WeightUnit = .lb
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Weight Type", selection: $weightType) {
                    ForEach(WeightType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if weightType != .barbell {
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

        let nextSortIndex = dayPlan.activeSortedWorkouts.count
        let unitToStore = weightType == .barbell ? defaultUnit : preferredUnit

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
}
