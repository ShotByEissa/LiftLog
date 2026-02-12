import SwiftData
import SwiftUI

struct LogWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var workout: WorkoutTemplate
    var dayPlan: DayPlan
    var weekIndex: Int
    var appConfig: AppConfig

    @State private var setDrafts: [SetDraft]
    @State private var currentUnit: WeightUnit
    @State private var sessionDate: Date = .now
    @State private var errorMessage: String?
    @State private var didLoadPreviousValues = false
    @State private var previousSetBaselines: [PreviousSetBaseline] = []
    @State private var hasPreviousSessionEntry = false

    @State private var isLoggingUnlocked = false
    @State private var showDiscardChangesAlert = false
    @State private var showDuplicateChoiceDialog = false
    @State private var showPlanSyncAlert = false
    @State private var pendingSaveContext: PendingSaveContext?

    init(workout: WorkoutTemplate, dayPlan: DayPlan, weekIndex: Int, appConfig: AppConfig) {
        self.workout = workout
        self.dayPlan = dayPlan
        self.weekIndex = weekIndex
        self.appConfig = appConfig

        let plateIDs = appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .map(\.id)
        _setDrafts = State(initialValue: SetDraft.plannedDefaults(
            warmUpCount: workout.plannedWarmUpSetCount,
            workingCount: workout.plannedWorkingSetCount,
            plateOptionIDs: plateIDs
        ))
        _currentUnit = State(initialValue: workout.preferredUnit)
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.name)
                            .font(.title2.bold())

                        Text("\(dayPlan.label) • \(sessionDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(isLoggingUnlocked ? "Logging Enabled" : "Locked")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isLoggingUnlocked ? .green : .secondary)
                    }

                    Spacer(minLength: 8)

                    if !workout.weightType.usesPlatePicker {
                        unitDropdownMenu
                            .opacity(isLoggingUnlocked ? 1 : 0.45)
                            .allowsHitTesting(isLoggingUnlocked)
                    }
                }
            }

            Section("Sets") {
                if didLoadPreviousValues && !hasPreviousSessionEntry {
                    Text("No previous session yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    ForEach(setDrafts.indices, id: \.self) { index in
                        if workout.weightType.usesPlatePicker {
                            platePickerSetRow(index: index)
                        } else {
                            numericSetRow(index: index)
                        }
                    }
                    .onDelete(perform: deleteSets)

                    Button("Add Set") {
                        addSet()
                    }

                    Button("Copy Last Set") {
                        copyLastSet()
                    }
                    .disabled(setDrafts.isEmpty || !isLoggingUnlocked)
                }
                .disabled(!isLoggingUnlocked)
                .opacity(isLoggingUnlocked ? 1 : 0.48)

                if !isLoggingUnlocked {
                    Text("Tap Begin Logging to unlock this workout.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Log Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    handleBackAction()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoggingUnlocked {
                    Button("Done") {
                        doneTapped()
                    }
                } else {
                    Button("Begin Logging") {
                        beginLogging()
                    }
                }
            }
        }
        .alert("Discard This Log?", isPresented: $showDiscardChangesAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Your in-progress changes for this workout are not saved until you tap Done.")
        }
        .confirmationDialog(
            "This workout already exists in today's session.",
            isPresented: $showDuplicateChoiceDialog,
            titleVisibility: .visible
        ) {
            Button("Replace Latest") {
                handleDuplicateChoice(.replaceLatest)
            }
            Button("Keep Both") {
                handleDuplicateChoice(.keepBoth)
            }
            Button("Cancel", role: .cancel) {
                pendingSaveContext = nil
            }
        }
        .alert("Update Future Defaults?", isPresented: $showPlanSyncAlert) {
            Button("No", role: .cancel) {
                finalizePendingSave(syncPlanDefaults: false)
            }
            Button("Yes") {
                finalizePendingSave(syncPlanDefaults: true)
            }
        } message: {
            Text("Apply this workout's warm-up and working set counts as the new plan defaults?")
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            loadMostRecentEntryIfAvailable()
        }
    }

    private var filteredPlateOptions: [PlateOption] {
        appConfig.plateCatalog
            .filter { $0.unit == appConfig.barWeightUnit }
            .sorted { $0.value > $1.value }
    }

    private var basePlateWeight: Double {
        workout.weightType == .barbell ? max(0, appConfig.barWeightValue) : 0
    }

    private func numericSetRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField(
                            "Weight",
                            text: Binding(
                                get: { setDrafts[index].loadText },
                                set: { setDrafts[index].loadText = $0 }
                            )
                        )
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                        Text(currentUnit.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                repsControl(for: index)
            }

            progressionLine(for: index, displayUnit: currentUnit)

            setTypeDropdown(for: index)
        }
        .padding(.vertical, 2)
    }

    private func platePickerSetRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Set \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if !filteredPlateOptions.isEmpty {
                    PlateBarPreview(tokens: plateTokens(for: index))
                        .frame(height: 56)
                }
            }

            if filteredPlateOptions.isEmpty {
                Text("No plates available for \(appConfig.barWeightUnit.title). Add them in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Total: \(totalForSet(index).prettyWeight) \(appConfig.barWeightUnit.rawValue)")
                    .font(.title3.weight(.semibold))

                progressionLine(for: index, displayUnit: appConfig.barWeightUnit)
                setTypeDropdown(for: index)

                plateTallyRow(for: index)
            }

            repsInlineControl(for: index)
        }
        .padding(.vertical, 2)
    }

    private var unitDropdownMenu: some View {
        Menu {
            ForEach(WeightUnit.allCases) { unit in
                Button {
                    guard isLoggingUnlocked else { return }
                    currentUnit = unit
                } label: {
                    if unit == currentUnit {
                        Label(unit.title, systemImage: "checkmark")
                    } else {
                        Text(unit.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(currentUnit.title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
        }
    }

    private func setTypeDropdown(for setIndex: Int) -> some View {
        let selected = setType(for: setIndex)

        return HStack(spacing: 8) {
            Text("Type")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(SetType.allCases) { type in
                    Button {
                        updateSetType(for: setIndex, type: type)
                    } label: {
                        if selected == type {
                            Label(type.title, systemImage: "checkmark")
                        } else {
                            Text(type.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selected.title)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
            }
        }
    }

    private func plateTallyRow(for setIndex: Int) -> some View {
        GeometryReader { proxy in
            let optionCount = max(filteredPlateOptions.count, 1)
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(optionCount - 1)
            let cardWidth = (proxy.size.width - totalSpacing) / CGFloat(optionCount)

            HStack(spacing: spacing) {
                ForEach(Array(filteredPlateOptions.enumerated()), id: \.element.id) { optionIndex, plate in
                    plateTallyControl(plate: plate, optionIndex: optionIndex, setIndex: setIndex)
                        .frame(width: cardWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 122)
    }

    private func plateTallyControl(plate: PlateOption, optionIndex: Int, setIndex: Int) -> some View {
        let count = plateCount(for: setIndex, plateID: plate.id)
        let accent = plateColor(for: optionIndex)
        let atMax = count >= 20

        return VStack(spacing: 4) {
            Button {
                updatePlateCount(for: setIndex, plateID: plate.id, delta: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(accent.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(atMax ? accent.opacity(0.4) : accent)
            .disabled(atMax)

            Text(plate.value.prettyWeight)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("x\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                updatePlateCount(for: setIndex, plateID: plate.id, delta: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(count > 0 ? .primary : .tertiary)
            .disabled(count == 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func repsInlineControl(for setIndex: Int) -> some View {
        HStack(spacing: 10) {
            Text("Reps")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                updateReps(for: setIndex, delta: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(repsValue(for: setIndex) > 0 ? .primary : .tertiary)
            .disabled(repsValue(for: setIndex) == 0)

            Text("\(repsValue(for: setIndex))")
                .font(.title2.monospacedDigit())
                .frame(minWidth: 32, alignment: .center)

            Button {
                updateReps(for: setIndex, delta: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
    }

    private func repsControl(for setIndex: Int) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Reps")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    updateReps(for: setIndex, delta: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(repsValue(for: setIndex) > 0 ? .primary : .tertiary)
                .disabled(repsValue(for: setIndex) == 0)

                Text("\(repsValue(for: setIndex))")
                    .monospacedDigit()
                    .frame(minWidth: 30, alignment: .center)

                Button {
                    updateReps(for: setIndex, delta: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 104, alignment: .trailing)
    }

    private func addSet() {
        guard isLoggingUnlocked else { return }
        let plateIDs = filteredPlateOptions.map(\.id)
        setDrafts.append(SetDraft.makeDefault(plateOptionIDs: plateIDs))
    }

    private func copyLastSet() {
        guard isLoggingUnlocked else { return }
        guard let last = setDrafts.last else { return }
        setDrafts.append(last.duplicate())
    }

    private func deleteSets(at offsets: IndexSet) {
        guard isLoggingUnlocked else { return }
        setDrafts.remove(atOffsets: offsets)
    }

    private func plateCount(for setIndex: Int, plateID: UUID) -> Int {
        setDrafts[setIndex].plateCounts[plateID] ?? 0
    }

    private func setPlateCount(_ count: Int, for setIndex: Int, plateID: UUID) {
        setDrafts[setIndex].plateCounts[plateID] = max(0, count)
    }

    private func updatePlateCount(for setIndex: Int, plateID: UUID, delta: Int) {
        guard isLoggingUnlocked else { return }
        let next = max(0, min(20, plateCount(for: setIndex, plateID: plateID) + delta))
        setPlateCount(next, for: setIndex, plateID: plateID)
    }

    private func plateColor(for optionIndex: Int) -> Color {
        let palette: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .indigo, .pink]
        return palette[optionIndex % palette.count]
    }

    private func plateTokens(for setIndex: Int) -> [PlateVisualToken] {
        filteredPlateOptions.enumerated().flatMap { optionIndex, plate -> [PlateVisualToken] in
            let count = plateCount(for: setIndex, plateID: plate.id)
            guard count > 0 else { return [PlateVisualToken]() }

            let color = plateColor(for: optionIndex)
            let height = plateHeight(for: plate.value)
            return (0..<count).map { tokenIndex in
                PlateVisualToken(
                    id: "\(plate.id.uuidString)-\(tokenIndex)",
                    color: color,
                    height: height
                )
            }
        }
    }

    private func plateHeight(for value: Double) -> CGFloat {
        let maxValue = filteredPlateOptions.map(\.value).max() ?? 1
        guard maxValue > 0 else { return 24 }
        let normalized = max(0.35, min(1, value / maxValue))
        return CGFloat(22 + (normalized * 28))
    }

    private func totalForSet(_ index: Int) -> Double {
        let perSide = filteredPlateOptions.reduce(0.0) { partial, plate in
            let count = Double(plateCount(for: index, plateID: plate.id))
            return partial + (plate.value * count)
        }
        return basePlateWeight + (2 * perSide)
    }

    private func repsValue(for setIndex: Int) -> Int {
        max(0, Int(setDrafts[setIndex].repsText) ?? 0)
    }

    private func setType(for setIndex: Int) -> SetType {
        guard setDrafts.indices.contains(setIndex) else { return .working }
        return setDrafts[setIndex].setType
    }

    private func updateSetType(for setIndex: Int, type: SetType) {
        guard isLoggingUnlocked else { return }
        guard setDrafts.indices.contains(setIndex) else { return }
        setDrafts[setIndex].setType = type
    }

    private func updateReps(for setIndex: Int, delta: Int) {
        guard isLoggingUnlocked else { return }
        let next = max(0, repsValue(for: setIndex) + delta)
        setDrafts[setIndex].repsText = "\(next)"
    }

    private func baseline(for setIndex: Int) -> PreviousSetBaseline? {
        let setNumber = setIndex + 1
        return previousSetBaselines.first { $0.setNumber == setNumber }
    }

    private func currentWeight(for setIndex: Int) -> (value: Double?, unit: WeightUnit?) {
        guard setDrafts.indices.contains(setIndex) else {
            return (nil, nil)
        }

        if workout.weightType.usesPlatePicker {
            return (totalForSet(setIndex), appConfig.barWeightUnit)
        }

        let raw = setDrafts[setIndex].loadText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(raw) else {
            return (nil, currentUnit)
        }
        return (max(0, parsed), currentUnit)
    }

    private func convertedWeight(_ value: Double, from: WeightUnit, to: WeightUnit) -> Double {
        guard from != to else { return value }

        let poundsPerKilogram = 2.2046226218
        switch (from, to) {
        case (.lb, .kg):
            return value / poundsPerKilogram
        case (.kg, .lb):
            return value * poundsPerKilogram
        default:
            return value
        }
    }

    private func weightDelta(for setIndex: Int, displayUnit: WeightUnit) -> Double? {
        guard let previous = baseline(for: setIndex),
              let previousValue = previous.weightValue,
              let previousUnit = previous.weightUnit else {
            return nil
        }

        let current = currentWeight(for: setIndex)
        guard let currentValue = current.value else {
            return nil
        }

        let convertedPrevious = convertedWeight(previousValue, from: previousUnit, to: displayUnit)
        let delta = currentValue - convertedPrevious
        return abs(delta) < 0.0001 ? 0 : delta
    }

    private func repsDelta(for setIndex: Int) -> Int? {
        guard let previous = baseline(for: setIndex) else {
            return nil
        }
        return repsValue(for: setIndex) - previous.reps
    }

    private func previousWeightText(for setIndex: Int, displayUnit: WeightUnit) -> String {
        guard let previous = baseline(for: setIndex),
              let previousValue = previous.weightValue,
              let previousUnit = previous.weightUnit else {
            return "—"
        }

        let convertedPrevious = convertedWeight(previousValue, from: previousUnit, to: displayUnit)
        return "\(convertedPrevious.prettyWeight) \(displayUnit.rawValue)"
    }

    private func weightDeltaText(for setIndex: Int, displayUnit: WeightUnit) -> String {
        guard let delta = weightDelta(for: setIndex, displayUnit: displayUnit) else {
            return "—"
        }
        return "\(signedWeight(delta)) \(displayUnit.rawValue)"
    }

    private func repsDeltaText(for setIndex: Int) -> String {
        guard let delta = repsDelta(for: setIndex) else {
            return "—"
        }

        let noun = abs(delta) == 1 ? "rep" : "reps"
        return "\(signedCount(delta)) \(noun)"
    }

    private func signedWeight(_ value: Double) -> String {
        if value > 0 { return "+\(value.prettyWeight)" }
        if value < 0 { return value.prettyWeight }
        return "0"
    }

    private func signedCount(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        return "\(value)"
    }

    private func deltaColor(for delta: Double?) -> Color {
        guard let delta else { return .secondary }
        if delta > 0.0001 { return .green }
        if delta < -0.0001 { return .orange }
        return .secondary
    }

    private func deltaColor(for delta: Int?) -> Color {
        guard let delta else { return .secondary }
        if delta > 0 { return .green }
        if delta < 0 { return .orange }
        return .secondary
    }

    @ViewBuilder
    private func progressionLine(for setIndex: Int, displayUnit: WeightUnit) -> some View {
        if hasPreviousSessionEntry {
            if let previous = baseline(for: setIndex) {
                HStack(spacing: 4) {
                    Text("Prev \(previousWeightText(for: setIndex, displayUnit: displayUnit)) x\(previous.reps)")
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("Δ")
                        .foregroundStyle(.secondary)
                    Text(weightDeltaText(for: setIndex, displayUnit: displayUnit))
                        .foregroundStyle(deltaColor(for: weightDelta(for: setIndex, displayUnit: displayUnit)))
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(repsDeltaText(for: setIndex))
                        .foregroundStyle(deltaColor(for: repsDelta(for: setIndex)))
                }
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            } else {
                Text("Prev — • Δ —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadMostRecentEntryIfAvailable() {
        guard !didLoadPreviousValues else { return }
        didLoadPreviousValues = true
        previousSetBaselines = []
        hasPreviousSessionEntry = false

        do {
            let descriptor = FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
            )
            let sessions = try modelContext.fetch(descriptor)

            guard let previousEntry = sessions.lazy.compactMap({ session in
                if let exact = session.entries.last(where: { $0.workoutTemplateId == workout.id }) {
                    return exact
                }

                return session.entries.last(where: { entry in
                    normalizeWorkoutName(entry.workoutNameSnapshot) == normalizeWorkoutName(workout.name)
                        && entry.weightTypeSnapshot == workout.weightType
                })
            }).first else {
                return
            }

            hasPreviousSessionEntry = true

            let sortedSets = previousEntry.sets.sorted { $0.setNumber < $1.setNumber }
            previousSetBaselines = sortedSets.map { set in
                if workout.weightType.usesPlatePicker {
                    return PreviousSetBaseline(
                        setNumber: max(1, set.setNumber),
                        reps: max(0, set.reps),
                        weightValue: set.computedTotalValue.map { max(0, $0) },
                        weightUnit: set.computedTotalUnit ?? set.barWeightUnitSnapshot
                    )
                }

                return PreviousSetBaseline(
                    setNumber: max(1, set.setNumber),
                    reps: max(0, set.reps),
                    weightValue: set.loadValue.map { max(0, $0) },
                    weightUnit: set.loadUnit
                )
            }
        } catch {
            print("Failed to load previous workout values: \(error)")
        }
    }

    private func beginLogging() {
        sessionDate = .now
        isLoggingUnlocked = true
    }

    private func handleBackAction() {
        if isLoggingUnlocked {
            showDiscardChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func doneTapped() {
        guard isLoggingUnlocked else { return }
        guard !setDrafts.isEmpty else {
            errorMessage = "Add at least one set before saving."
            return
        }

        do {
            pendingSaveContext = try buildPendingSaveContext()

            guard let context = pendingSaveContext else { return }

            if !context.duplicateEntryIndices.isEmpty {
                showDuplicateChoiceDialog = true
                return
            }

            if context.structureChangedFromPlan {
                showPlanSyncAlert = true
                return
            }

            finalizePendingSave(syncPlanDefaults: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildPendingSaveContext() throws -> PendingSaveContext {
        let calendar = Calendar.current
        let sessionDayStart = calendar.startOfDay(for: sessionDate)

        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        let sessions = try modelContext.fetch(descriptor)

        let existingSession = sessions.first { session in
            session.weekIndex == weekIndex
                && session.weekday == dayPlan.weekday
                && (
                    calendar.isDate(session.sessionDayStart, inSameDayAs: sessionDayStart)
                        || calendar.isDate(session.date, inSameDayAs: sessionDayStart)
                )
        }

        let duplicateEntryIndices: [Int] = {
            guard let session = existingSession else { return [] }
            return session.entries.indices.filter { index in
                matchesWorkout(entry: session.entries[index])
            }
        }()

        let warmUpCount = setDrafts.filter { $0.setType == .warmUp }.count
        let workingCount = setDrafts.filter { $0.setType == .working }.count

        let structureChanged = warmUpCount != max(0, workout.plannedWarmUpSetCount)
            || workingCount != max(1, workout.plannedWorkingSetCount)

        return PendingSaveContext(
            drafts: setDrafts,
            unit: currentUnit,
            date: sessionDate,
            sessionDayStart: sessionDayStart,
            existingSession: existingSession,
            duplicateEntryIndices: duplicateEntryIndices,
            duplicateResolution: .keepBoth,
            structureChangedFromPlan: structureChanged
        )
    }

    private func handleDuplicateChoice(_ resolution: DuplicateResolution) {
        guard var context = pendingSaveContext else { return }
        context.duplicateResolution = resolution
        pendingSaveContext = context

        if context.structureChangedFromPlan {
            showPlanSyncAlert = true
            return
        }

        finalizePendingSave(syncPlanDefaults: false)
    }

    private func finalizePendingSave(syncPlanDefaults: Bool) {
        guard let context = pendingSaveContext else { return }

        let session: WorkoutSession
        if let existing = context.existingSession {
            session = existing
        } else {
            session = WorkoutSession(
                date: context.date,
                sessionDayStart: context.sessionDayStart,
                weekIndex: weekIndex,
                weekday: dayPlan.weekday,
                dayLabelSnapshot: dayPlan.label,
                entries: []
            )
            modelContext.insert(session)
        }

        if context.duplicateResolution == .replaceLatest,
           let replaceIndex = context.duplicateEntryIndices.max(),
           session.entries.indices.contains(replaceIndex) {
            let replaced = session.entries[replaceIndex]
            session.entries.remove(at: replaceIndex)
            modelContext.delete(replaced)
        }

        let entry = SessionEntry(
            workoutTemplateId: workout.id,
            workoutNameSnapshot: workout.name,
            weightTypeSnapshot: workout.weightType,
            sets: buildLoggedSets(from: context.drafts, unit: context.unit)
        )

        session.entries.append(entry)
        session.date = context.date
        session.sessionDayStart = context.sessionDayStart
        session.dayLabelSnapshot = dayPlan.label

        if !workout.weightType.usesPlatePicker {
            workout.preferredUnit = context.unit
        }

        if syncPlanDefaults {
            syncTemplatePlanDefaults(using: context.drafts)
        }

        do {
            try modelContext.save()
            pendingSaveContext = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncTemplatePlanDefaults(using drafts: [SetDraft]) {
        let warmUpCount = drafts.filter { $0.setType == .warmUp }.count
        let workingCount = drafts.filter { $0.setType == .working }.count

        workout.plannedWarmUpSetCount = max(0, warmUpCount)
        workout.plannedWorkingSetCount = max(1, workingCount)
    }

    private func matchesWorkout(entry: SessionEntry) -> Bool {
        if entry.workoutTemplateId == workout.id {
            return true
        }

        return entry.weightTypeSnapshot == workout.weightType
            && normalizeWorkoutName(entry.workoutNameSnapshot) == normalizeWorkoutName(workout.name)
    }

    private func normalizeWorkoutName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func buildLoggedSets(from drafts: [SetDraft], unit: WeightUnit) -> [LoggedSet] {
        drafts.enumerated().map { index, draft in
            let reps = max(0, Int(draft.repsText) ?? 0)

            if workout.weightType.usesPlatePicker {
                let plateCounts: [PlateCount] = filteredPlateOptions.compactMap { option in
                    let count = max(0, draft.plateCounts[option.id] ?? 0)
                    guard count > 0 else { return nil }
                    return PlateCount(plateOptionId: option.id, countPerSide: count)
                }

                let total = basePlateWeight + (2 * filteredPlateOptions.reduce(0.0) { partial, plate in
                    let count = Double(max(0, draft.plateCounts[plate.id] ?? 0))
                    return partial + (plate.value * count)
                })

                return LoggedSet(
                    setNumber: index + 1,
                    reps: reps,
                    setType: draft.setType,
                    perSidePlates: plateCounts,
                    barWeightValueSnapshot: basePlateWeight,
                    barWeightUnitSnapshot: appConfig.barWeightUnit,
                    computedTotalValue: total,
                    computedTotalUnit: appConfig.barWeightUnit
                )
            }

            let load = max(0, Double(draft.loadText) ?? 0)
            return LoggedSet(
                setNumber: index + 1,
                reps: reps,
                setType: draft.setType,
                loadValue: load,
                loadUnit: unit
            )
        }
    }
}

private enum DuplicateResolution {
    case replaceLatest
    case keepBoth
}

private struct PendingSaveContext {
    var drafts: [SetDraft]
    var unit: WeightUnit
    var date: Date
    var sessionDayStart: Date
    var existingSession: WorkoutSession?
    var duplicateEntryIndices: [Int]
    var duplicateResolution: DuplicateResolution
    var structureChangedFromPlan: Bool
}

private struct SetDraft: Identifiable {
    let id = UUID()
    var repsText: String
    var loadText: String
    var setType: SetType
    var plateCounts: [UUID: Int]

    static func makeDefault(plateOptionIDs: [UUID], setType: SetType = .working) -> SetDraft {
        SetDraft(
            repsText: "",
            loadText: "",
            setType: setType,
            plateCounts: Dictionary(uniqueKeysWithValues: plateOptionIDs.map { ($0, 0) })
        )
    }

    static func plannedDefaults(warmUpCount: Int, workingCount: Int, plateOptionIDs: [UUID]) -> [SetDraft] {
        let warmUpSets = (0..<max(0, warmUpCount)).map { _ in
            makeDefault(plateOptionIDs: plateOptionIDs, setType: .warmUp)
        }
        let workingSets = (0..<max(1, workingCount)).map { _ in
            makeDefault(plateOptionIDs: plateOptionIDs, setType: .working)
        }

        let combined = warmUpSets + workingSets
        return combined.isEmpty ? [makeDefault(plateOptionIDs: plateOptionIDs, setType: .working)] : combined
    }

    func duplicate() -> SetDraft {
        SetDraft(repsText: repsText, loadText: loadText, setType: setType, plateCounts: plateCounts)
    }
}

private struct PreviousSetBaseline {
    var setNumber: Int
    var reps: Int
    var weightValue: Double?
    var weightUnit: WeightUnit?
}

private struct PlateVisualToken: Identifiable {
    let id: String
    let color: Color
    let height: CGFloat
}

private struct PlateBarPreview: View {
    let tokens: [PlateVisualToken]
    private let centerBlockWidth: CGFloat = 18
    private let horizontalPadding: CGFloat = 32
    private let targetLeftShaft: CGFloat = 20

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 14)

            HStack(spacing: 4) {
                Spacer(minLength: 0)

                plateSide(tokens: Array(tokens.reversed()))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 18, height: 36)
            }
            .padding(.horizontal, 16)
        }
        .frame(width: previewWidth)
    }

    private func plateSide(tokens: [PlateVisualToken]) -> some View {
        let tokenCount = max(tokens.count, 1)
        let plateWidth = max(4, min(9, 96 / CGFloat(tokenCount)))
        let spacing = max(1, plateWidth * 0.2)

        return HStack(spacing: spacing) {
            ForEach(tokens) { token in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(token.color.gradient)
                    .frame(width: plateWidth, height: token.height)
            }
        }
    }

    private var previewWidth: CGFloat {
        let tokenCount = CGFloat(max(tokens.count, 1))
        let plateWidth = max(4, min(9, 96 / tokenCount))
        let spacing = max(1, plateWidth * 0.2)
        let sideWidth = (plateWidth * tokenCount) + (spacing * max(0, tokenCount - 1))
        let rawWidth = sideWidth + centerBlockWidth + targetLeftShaft + horizontalPadding
        return max(120, min(190, rawWidth))
    }
}
