import SwiftData
import SwiftUI

struct WorkoutDayView: View {
    @Environment(\.modelContext) private var modelContext

    var appConfig: AppConfig
    var splitPlan: SplitPlan

    @State private var selectedWeekIndex: Int = 1
    @State private var selectedWeekday: Weekday = .sunday
    @State private var showAddWorkout = false

    @State private var workoutToRename: WorkoutTemplate?
    @State private var renameValue: String = ""

    var body: some View {
        VStack(spacing: 10) {
            weekDaySelector

            if let dayPlan = currentDayPlan {
                workoutList(for: dayPlan)
            } else {
                Spacer()
                ContentUnavailableView(
                    "No Day Selected",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Configure this week in Settings to add workout days.")
                )
                Spacer()
            }
        }
        .navigationTitle("Workout")
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
                .disabled(currentDayPlan == nil)
            }
        }
        .sheet(isPresented: $showAddWorkout) {
            if let dayPlan = currentDayPlan {
                NavigationStack {
                    AddWorkoutView(dayPlan: dayPlan, defaultUnit: appConfig.barWeightUnit)
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
        .onAppear {
            selectedWeekIndex = min(max(1, selectedWeekIndex), appConfig.splitLengthWeeks)
            ensureValidDaySelection()
        }
        .onChange(of: selectedWeekIndex) { _, _ in
            ensureValidDaySelection()
        }
    }

    private var weekDaySelector: some View {
        VStack(spacing: 10) {
            Picker("Week", selection: $selectedWeekIndex) {
                ForEach(1...appConfig.splitLengthWeeks, id: \.self) { week in
                    Text("Week \(week)").tag(week)
                }
            }
            .pickerStyle(.segmented)

            if !availableDayPlans.isEmpty {
                Picker("Day", selection: $selectedWeekday) {
                    ForEach(availableDayPlans, id: \.weekday.rawValue) { dayPlan in
                        Text(dayPlan.weekday.shortName).tag(dayPlan.weekday)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func workoutList(for dayPlan: DayPlan) -> some View {
        let workouts = dayPlan.activeSortedWorkouts

        return List {
            Section(dayPlan.label) {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to add your first workout for \(dayPlan.label).")
                    )
                } else {
                    ForEach(workouts, id: \.id) { workout in
                        NavigationLink {
                            LogWorkoutView(
                                workout: workout,
                                dayPlan: dayPlan,
                                weekIndex: selectedWeekIndex,
                                appConfig: appConfig
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.body)
                                Text(workout.weightType.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Rename") {
                                workoutToRename = workout
                                renameValue = workout.name
                            }

                            Button("Delete", role: .destructive) {
                                delete(workout: workout, from: dayPlan)
                            }
                        }
                    }
                    .onMove { source, destination in
                        moveWorkouts(in: dayPlan, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteWorkouts(in: dayPlan, offsets: offsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var currentWeek: PlanWeek? {
        splitPlan.week(for: selectedWeekIndex)
    }

    private var availableDayPlans: [DayPlan] {
        currentWeek?.sortedDayPlans ?? []
    }

    private var currentDayPlan: DayPlan? {
        availableDayPlans.first { $0.weekday == selectedWeekday }
    }

    private func ensureValidDaySelection() {
        guard let firstDay = availableDayPlans.first else { return }
        if !availableDayPlans.contains(where: { $0.weekday == selectedWeekday }) {
            selectedWeekday = firstDay.weekday
        }
    }

    private func moveWorkouts(in dayPlan: DayPlan, from source: IndexSet, to destination: Int) {
        var ordered = dayPlan.activeSortedWorkouts
        ordered.move(fromOffsets: source, toOffset: destination)

        for (index, workout) in ordered.enumerated() {
            workout.sortIndex = index
        }

        saveChanges()
    }

    private func deleteWorkouts(in dayPlan: DayPlan, offsets: IndexSet) {
        let ordered = dayPlan.activeSortedWorkouts
        let targets = offsets.map { ordered[$0] }
        for workout in targets {
            delete(workout: workout, from: dayPlan)
        }
    }

    private func delete(workout: WorkoutTemplate, from dayPlan: DayPlan) {
        dayPlan.workouts.removeAll(where: { $0.id == workout.id })
        modelContext.delete(workout)

        let remaining = dayPlan.activeSortedWorkouts
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
            print("Failed to save day view changes: \(error)")
        }
    }
}
