import SwiftData
import SwiftUI

struct WorkoutDayView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("profileFirstName") private var profileFirstName: String = ""

    var appConfig: AppConfig

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var showAddDay = false
    @State private var newDayName: String = ""
    @State private var errorMessage: String?

    @State private var dayToRename: WorkoutDay?
    @State private var renameValue: String = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        mainContent
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddDay = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Add Workout Day", isPresented: $showAddDay) {
                TextField("Day name", text: $newDayName)
                Button("Cancel", role: .cancel) { newDayName = "" }
                Button("Add") { addDay() }
            } message: {
                Text("Give your workout day a name (e.g. Push, Pull, Legs).")
            }
            .alert("Rename Workout Day", isPresented: Binding(
                get: { dayToRename != nil },
                set: { if !$0 { dayToRename = nil; renameValue = "" } }
            )) {
                TextField("Day name", text: $renameValue)
                Button("Cancel", role: .cancel) { dayToRename = nil; renameValue = "" }
                Button("Save") { saveRename() }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            welcomeHeader

            if appConfig.sortedWorkoutDays.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Workout Days",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Tap + to create your first workout day.")
                )
                Spacer()
            } else {
                cardGrid
            }
        }
    }

    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(appConfig.sortedWorkoutDays, id: \.id) { workoutDay in
                    NavigationLink {
                        WorkoutExerciseListView(workoutDay: workoutDay, appConfig: appConfig)
                    } label: {
                        dayCard(for: workoutDay)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            dayToRename = workoutDay
                            renameValue = workoutDay.label
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteDay(workoutDay)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hey \(displayFirstName).")
                .font(.title.weight(.semibold))
            Text("Let's work!")
                .font(.title.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func dayCard(for workoutDay: WorkoutDay) -> some View {
        let exerciseCount = workoutDay.activeSortedWorkouts.count
        let completedToday = isDayCompletedToday(workoutDay)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workoutDay.label)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                if completedToday {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }

            Text("\(exerciseCount) \(exerciseCount == 1 ? "exercise" : "exercises")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    private var displayFirstName: String {
        let trimmed = profileFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Athlete" : trimmed
    }

    private func isDayCompletedToday(_ workoutDay: WorkoutDay) -> Bool {
        let today = Calendar.current.startOfDay(for: Date.now)
        return sessions.contains { session in
            session.dayLabelSnapshot == workoutDay.label
                && Calendar.current.isDate(session.sessionDayStart, inSameDayAs: today)
        }
    }

    private func addDay() {
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
        saveChanges()
    }

    private func deleteDay(_ workoutDay: WorkoutDay) {
        appConfig.workoutDays.removeAll { $0.id == workoutDay.id }
        modelContext.delete(workoutDay)

        for (index, day) in appConfig.sortedWorkoutDays.enumerated() {
            day.sortIndex = index
        }

        saveChanges()
    }

    private func saveRename() {
        guard let day = dayToRename else { return }
        let trimmed = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            day.label = trimmed
            saveChanges()
        }

        dayToRename = nil
        renameValue = ""
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
