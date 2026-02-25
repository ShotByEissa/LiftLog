import SwiftData
import SwiftUI

struct WorkoutExerciseListView: View {
    @Environment(\.modelContext) private var modelContext

    var workoutDay: WorkoutDay
    var appConfig: AppConfig

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var showAddWorkout = false
    @State private var showEditWorkoutPlan = false
    @State private var workoutToRename: WorkoutTemplate?
    @State private var workoutToEditPlan: WorkoutTemplate?
    @State private var renameValue: String = ""

    var body: some View {
        let workouts = workoutDay.activeSortedWorkouts

        List {
            Section {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to plan your first workout for \(workoutDay.label).")
                    )
                } else {
                    ForEach(workouts, id: \.id) { workout in
                        NavigationLink {
                            LogWorkoutView(
                                workout: workout,
                                workoutDay: workoutDay,
                                appConfig: appConfig
                            )
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.name)
                                        .font(.body)
                                    Text(workout.weightType.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 6)

                                if isWorkoutCompletedToday(workout) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Logged today")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit Plan") {
                                workoutToEditPlan = workout
                                showEditWorkoutPlan = true
                            }

                            Button("Rename") {
                                workoutToRename = workout
                                renameValue = workout.name
                            }

                            Button("Delete", role: .destructive) {
                                delete(workout: workout)
                            }
                        }
                    }
                    .onMove { source, destination in
                        moveWorkouts(from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteWorkouts(offsets: offsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(workoutDay.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddWorkout = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddWorkout) {
            NavigationStack {
                AddWorkoutView(workoutDay: workoutDay, defaultUnit: appConfig.barWeightUnit)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showEditWorkoutPlan, onDismiss: {
            workoutToEditPlan = nil
        }) {
            if let workout = workoutToEditPlan {
                NavigationStack {
                    AddWorkoutView(
                        workoutDay: workoutDay,
                        defaultUnit: appConfig.barWeightUnit,
                        workoutToEdit: workout
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
        .alert("Rename Workout", isPresented: Binding(
            get: { workoutToRename != nil },
            set: { isPresented in
                if !isPresented {
                    workoutToRename = nil
                    renameValue = ""
                }
            }
        )) {
            TextField("Workout name", text: $renameValue)
            Button("Cancel", role: .cancel) {
                workoutToRename = nil
                renameValue = ""
            }
            Button("Save") {
                saveRename()
            }
        }
    }

    private func isWorkoutCompletedToday(_ workout: WorkoutTemplate) -> Bool {
        let today = Calendar.current.startOfDay(for: Date.now)

        guard let session = sessions.first(where: { session in
            session.dayLabelSnapshot == workoutDay.label
                && Calendar.current.isDate(session.sessionDayStart, inSameDayAs: today)
        }) else {
            return false
        }

        let normalizedName = workout.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return session.entries.contains { entry in
            if entry.workoutTemplateId == workout.id {
                return true
            }
            return entry.weightTypeSnapshot == workout.weightType
                && entry.workoutNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
    }

    private func moveWorkouts(from source: IndexSet, to destination: Int) {
        var ordered = workoutDay.activeSortedWorkouts
        ordered.move(fromOffsets: source, toOffset: destination)

        for (index, workout) in ordered.enumerated() {
            workout.sortIndex = index
        }

        saveChanges()
    }

    private func deleteWorkouts(offsets: IndexSet) {
        let ordered = workoutDay.activeSortedWorkouts
        let targets = offsets.map { ordered[$0] }
        for workout in targets {
            delete(workout: workout)
        }
    }

    private func delete(workout: WorkoutTemplate) {
        workoutDay.workouts.removeAll(where: { $0.id == workout.id })
        modelContext.delete(workout)

        let remaining = workoutDay.activeSortedWorkouts
        for (index, template) in remaining.enumerated() {
            template.sortIndex = index
        }

        saveChanges()
    }

    private func saveRename() {
        guard let workout = workoutToRename else { return }
        let trimmed = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            workout.name = trimmed
            saveChanges()
        }

        workoutToRename = nil
        renameValue = ""
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save exercise list changes: \(error)")
        }
    }
}
