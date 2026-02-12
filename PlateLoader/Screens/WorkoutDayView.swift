import SwiftData
import SwiftUI

struct WorkoutDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("profileFirstName") private var profileFirstName: String = ""

    var appConfig: AppConfig
    var splitPlan: SplitPlan

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var selectedWeekIndex: Int = 1
    @State private var selectedWeekday: Weekday = .sunday
    @State private var showAddWorkout = false
    @State private var showEditWorkoutPlan = false
    @State private var hasAutoSelectedForCurrentAppearance = false

    @State private var workoutToRename: WorkoutTemplate?
    @State private var workoutToEditPlan: WorkoutTemplate?
    @State private var renameValue: String = ""

    var body: some View {
        VStack(spacing: 10) {
            welcomeHeader
            weekDaySelector

            if let dayPlan = currentDayPlan {
                daySwitcher(dayPlan)
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
        .navigationTitle("")
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
        .sheet(isPresented: $showEditWorkoutPlan, onDismiss: {
            workoutToEditPlan = nil
        }) {
            if let dayPlan = currentDayPlan, let workout = workoutToEditPlan {
                NavigationStack {
                    AddWorkoutView(
                        dayPlan: dayPlan,
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
        .onAppear {
            autoSelectFromCalendar(force: false)
        }
        .onDisappear {
            hasAutoSelectedForCurrentAppearance = false
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            autoSelectFromCalendar(force: true)
        }
        .onChange(of: selectedWeekIndex) { _, _ in
            ensureValidDaySelection()
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

    private var weekDaySelector: some View {
        VStack(spacing: 10) {
            Picker("Week", selection: $selectedWeekIndex) {
                ForEach(1...appConfig.splitLengthWeeks, id: \.self) { week in
                    Text("Week \(week)").tag(week)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func daySwitcher(_ dayPlan: DayPlan) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    moveToAdjacentDay(next: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canMoveToPreviousDay ? .primary : .tertiary)
                .disabled(!canMoveToPreviousDay)

                Spacer()

                VStack(spacing: 2) {
                    Text(dayPlan.weekday.fullName)
                        .font(.title3.weight(.bold))
                    Text(dayDetailLabel(for: dayPlan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    moveToAdjacentDay(next: true)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canMoveToNextDay ? .primary : .tertiary)
                .disabled(!canMoveToNextDay)
            }

            if availableDayPlans.count > 1 {
                HStack(spacing: 6) {
                    ForEach(availableDayPlans, id: \.weekday.rawValue) { day in
                        Capsule()
                            .fill(day.weekday == selectedWeekday ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: day.weekday == selectedWeekday ? 18 : 6, height: 6)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedWeekday)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
        .contentShape(Rectangle())
        .gesture(daySwipeGesture)
        .accessibilityHint("Swipe left or right to change day")
    }

    private func workoutList(for dayPlan: DayPlan) -> some View {
        let workouts = dayPlan.activeSortedWorkouts

        return List {
            Section {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to plan your first workout for \(dayPlan.label).")
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

    private func dayDetailLabel(for dayPlan: DayPlan) -> String {
        let trimmed = dayPlan.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare(dayPlan.weekday.fullName) == .orderedSame {
            return "Set a focus label in Settings"
        }
        return trimmed
    }

    private var displayFirstName: String {
        let trimmed = profileFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Athlete" : trimmed
    }

    private var currentDayIndex: Int? {
        availableDayPlans.firstIndex(where: { $0.weekday == selectedWeekday })
    }

    private var canMoveToPreviousDay: Bool {
        guard let index = currentDayIndex else { return false }
        return index > availableDayPlans.startIndex
    }

    private var canMoveToNextDay: Bool {
        guard let index = currentDayIndex else { return false }
        return index < availableDayPlans.index(before: availableDayPlans.endIndex)
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard abs(value.translation.width) > 40 else { return }
                if value.translation.width < 0 {
                    moveToAdjacentDay(next: true)
                } else {
                    moveToAdjacentDay(next: false)
                }
            }
    }

    private func moveToAdjacentDay(next: Bool) {
        guard let currentIndex = availableDayPlans.firstIndex(where: { $0.weekday == selectedWeekday }) else { return }
        let targetIndex = next ? currentIndex + 1 : currentIndex - 1
        guard availableDayPlans.indices.contains(targetIndex) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedWeekday = availableDayPlans[targetIndex].weekday
        }
    }

    private func ensureValidDaySelection() {
        guard let firstDay = availableDayPlans.first else { return }
        if !availableDayPlans.contains(where: { $0.weekday == selectedWeekday }) {
            selectedWeekday = firstDay.weekday
        }
    }

    private func autoSelectFromCalendar(force: Bool) {
        if !force && hasAutoSelectedForCurrentAppearance {
            return
        }
        hasAutoSelectedForCurrentAppearance = true

        selectedWeekIndex = min(max(1, selectedWeekIndex), max(1, appConfig.splitLengthWeeks))

        guard let selection = automaticSelectionForCurrentDate() else {
            ensureValidDaySelection()
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedWeekIndex = selection.weekIndex
            selectedWeekday = selection.weekday
        }
    }

    private func automaticSelectionForCurrentDate() -> DaySelection? {
        let today = startOfDay(Date.now)
        let currentWeekIndex = splitWeekIndex(for: today)
        let todayWeekday = weekday(for: today)

        if weekHasDay(weekIndex: currentWeekIndex, weekday: todayWeekday) {
            return DaySelection(weekIndex: currentWeekIndex, weekday: todayWeekday)
        }

        let maxSearchDays = max(1, appConfig.splitLengthWeeks * 7)
        for dayOffset in 1...maxSearchDays {
            guard let candidateDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }

            let candidateWeek = splitWeekIndex(for: candidateDate)
            let candidateWeekday = weekday(for: candidateDate)

            if weekHasDay(weekIndex: candidateWeek, weekday: candidateWeekday) {
                return DaySelection(weekIndex: candidateWeek, weekday: candidateWeekday)
            }
        }

        if let firstInComputedWeek = splitPlan.week(for: currentWeekIndex)?.sortedDayPlans.first?.weekday {
            return DaySelection(weekIndex: currentWeekIndex, weekday: firstInComputedWeek)
        }

        if let firstAnywhere = firstAvailableDaySelection {
            return firstAnywhere
        }

        return nil
    }

    private var firstAvailableDaySelection: DaySelection? {
        for week in splitPlan.sortedWeeks {
            if let day = week.sortedDayPlans.first {
                return DaySelection(weekIndex: week.weekIndex, weekday: day.weekday)
            }
        }
        return nil
    }

    private func weekHasDay(weekIndex: Int, weekday: Weekday) -> Bool {
        splitPlan.week(for: weekIndex)?
            .sortedDayPlans
            .contains(where: { $0.weekday == weekday }) ?? false
    }

    private func splitWeekIndex(for date: Date) -> Int {
        let calendar = Calendar.current
        let anchor = startOfDay(appConfig.createdAt)
        let target = startOfDay(date)
        let rawDayDiff = calendar.dateComponents([.day], from: anchor, to: target).day ?? 0
        let daysSinceAnchor = max(0, rawDayDiff)
        let splitLength = max(1, appConfig.splitLengthWeeks)
        return ((daysSinceAnchor / 7) % splitLength) + 1
    }

    private func weekday(for date: Date) -> Weekday {
        let raw = Calendar.current.component(.weekday, from: date)
        return Weekday(rawValue: raw) ?? .sunday
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func isWorkoutCompletedToday(_ workout: WorkoutTemplate) -> Bool {
        guard let session = todayWorkoutSession else { return false }
        let todaySelection = todayDaySelection
        let normalizedWorkoutName = normalizeWorkoutName(workout.name)

        return session.entries.contains { entry in
            if entry.workoutTemplateId == workout.id {
                return true
            }

            let isTodayTemplate = workout.dayPlan?.weekday == todaySelection.weekday
                && workout.dayPlan?.planWeek?.weekIndex == todaySelection.weekIndex
            guard isTodayTemplate else { return false }

            return entry.weightTypeSnapshot == workout.weightType
                && normalizeWorkoutName(entry.workoutNameSnapshot) == normalizedWorkoutName
        }
    }

    private var todayDaySelection: DaySelection {
        let today = startOfDay(Date.now)
        return DaySelection(weekIndex: splitWeekIndex(for: today), weekday: weekday(for: today))
    }

    private var todayWorkoutSession: WorkoutSession? {
        let today = startOfDay(Date.now)
        let todaySelection = todayDaySelection
        let calendar = Calendar.current

        return sessions.first { session in
            guard session.weekIndex == todaySelection.weekIndex && session.weekday == todaySelection.weekday else {
                return false
            }

            return calendar.isDate(session.sessionDayStart, inSameDayAs: today)
                || calendar.isDate(session.date, inSameDayAs: today)
        }
    }

    private func normalizeWorkoutName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

private struct DaySelection {
    var weekIndex: Int
    var weekday: Weekday
}
