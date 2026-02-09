import Foundation
import SwiftData

enum WeightType: String, Codable, CaseIterable, Identifiable {
    case dumbbell
    case machine
    case barbell
    case plateLoaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .barbell: return "Barbell"
        case .plateLoaded: return "Plate Loaded"
        }
    }

    var usesPlatePicker: Bool {
        self == .barbell || self == .plateLoaded
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case lb
    case kg

    var id: String { rawValue }

    var title: String {
        rawValue.uppercased()
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

@Model
final class AppConfig {
    var splitLengthWeeks: Int
    var createdAt: Date
    var barWeightValue: Double
    var barWeightUnit: WeightUnit

    @Relationship(deleteRule: .cascade, inverse: \PlateOption.appConfig)
    var plateCatalog: [PlateOption]

    init(
        splitLengthWeeks: Int,
        createdAt: Date = .now,
        barWeightValue: Double,
        barWeightUnit: WeightUnit,
        plateCatalog: [PlateOption] = []
    ) {
        self.splitLengthWeeks = AppConfig.clampSplitLength(splitLengthWeeks)
        self.createdAt = createdAt
        self.barWeightValue = max(0, barWeightValue)
        self.barWeightUnit = barWeightUnit
        self.plateCatalog = plateCatalog
    }

    static func clampSplitLength(_ value: Int) -> Int {
        min(max(value, 1), 4)
    }
}

@Model
final class SplitPlan {
    @Relationship(deleteRule: .cascade, inverse: \PlanWeek.splitPlan)
    var weeks: [PlanWeek]

    init(weeks: [PlanWeek] = []) {
        self.weeks = weeks
    }
}

@Model
final class PlanWeek {
    var weekIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \DayPlan.planWeek)
    var dayPlans: [DayPlan]

    var splitPlan: SplitPlan?

    init(weekIndex: Int, dayPlans: [DayPlan] = []) {
        self.weekIndex = weekIndex
        self.dayPlans = dayPlans
    }
}

@Model
final class DayPlan {
    var weekday: Weekday
    var label: String

    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.dayPlan)
    var workouts: [WorkoutTemplate]

    var planWeek: PlanWeek?

    init(weekday: Weekday, label: String, workouts: [WorkoutTemplate] = []) {
        self.weekday = weekday
        self.label = label
        self.workouts = workouts
    }
}

@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var weightType: WeightType
    var preferredUnit: WeightUnit
    var sortIndex: Int
    var isArchived: Bool

    var dayPlan: DayPlan?

    init(
        id: UUID = UUID(),
        name: String,
        weightType: WeightType,
        preferredUnit: WeightUnit,
        sortIndex: Int,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.weightType = weightType
        self.preferredUnit = preferredUnit
        self.sortIndex = max(0, sortIndex)
        self.isArchived = isArchived
    }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weekIndex: Int
    var weekday: Weekday
    var dayLabelSnapshot: String

    @Relationship(deleteRule: .cascade, inverse: \SessionEntry.session)
    var entries: [SessionEntry]

    init(
        id: UUID = UUID(),
        date: Date,
        weekIndex: Int,
        weekday: Weekday,
        dayLabelSnapshot: String,
        entries: [SessionEntry] = []
    ) {
        self.id = id
        self.date = date
        self.weekIndex = max(1, weekIndex)
        self.weekday = weekday
        self.dayLabelSnapshot = dayLabelSnapshot
        self.entries = entries
    }
}

@Model
final class SessionEntry {
    var workoutTemplateId: UUID
    var workoutNameSnapshot: String
    var weightTypeSnapshot: WeightType

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.sessionEntry)
    var sets: [LoggedSet]

    var session: WorkoutSession?

    init(
        workoutTemplateId: UUID,
        workoutNameSnapshot: String,
        weightTypeSnapshot: WeightType,
        sets: [LoggedSet] = []
    ) {
        self.workoutTemplateId = workoutTemplateId
        self.workoutNameSnapshot = workoutNameSnapshot
        self.weightTypeSnapshot = weightTypeSnapshot
        self.sets = sets
    }
}

@Model
final class LoggedSet {
    var setNumber: Int
    var reps: Int

    // Dumbbell/Machine
    var loadValue: Double?
    var loadUnit: WeightUnit?

    // Barbell
    @Relationship(deleteRule: .cascade, inverse: \PlateCount.loggedSet)
    var perSidePlates: [PlateCount]
    var barWeightValueSnapshot: Double?
    var barWeightUnitSnapshot: WeightUnit?
    var computedTotalValue: Double?
    var computedTotalUnit: WeightUnit?

    var sessionEntry: SessionEntry?

    init(
        setNumber: Int,
        reps: Int,
        loadValue: Double? = nil,
        loadUnit: WeightUnit? = nil,
        perSidePlates: [PlateCount] = [],
        barWeightValueSnapshot: Double? = nil,
        barWeightUnitSnapshot: WeightUnit? = nil,
        computedTotalValue: Double? = nil,
        computedTotalUnit: WeightUnit? = nil
    ) {
        self.setNumber = max(1, setNumber)
        self.reps = max(0, reps)
        self.loadValue = loadValue.map { max(0, $0) }
        self.loadUnit = loadUnit
        self.perSidePlates = perSidePlates
        self.barWeightValueSnapshot = barWeightValueSnapshot.map { max(0, $0) }
        self.barWeightUnitSnapshot = barWeightUnitSnapshot
        self.computedTotalValue = computedTotalValue.map { max(0, $0) }
        self.computedTotalUnit = computedTotalUnit
    }
}

@Model
final class PlateOption {
    @Attribute(.unique) var id: UUID
    var value: Double
    var unit: WeightUnit
    var label: String

    var appConfig: AppConfig?

    init(id: UUID = UUID(), value: Double, unit: WeightUnit, label: String) {
        self.id = id
        self.value = max(0, value)
        self.unit = unit
        self.label = label
    }
}

@Model
final class PlateCount {
    var plateOptionId: UUID
    var countPerSide: Int

    var loggedSet: LoggedSet?

    init(plateOptionId: UUID, countPerSide: Int) {
        self.plateOptionId = plateOptionId
        self.countPerSide = max(0, countPerSide)
    }
}

extension SplitPlan {
    var sortedWeeks: [PlanWeek] {
        weeks.sorted { $0.weekIndex < $1.weekIndex }
    }

    func week(for index: Int) -> PlanWeek? {
        weeks.first { $0.weekIndex == index }
    }
}

extension PlanWeek {
    var sortedDayPlans: [DayPlan] {
        dayPlans.sorted { $0.weekday.rawValue < $1.weekday.rawValue }
    }

    func dayPlan(for weekday: Weekday) -> DayPlan? {
        dayPlans.first { $0.weekday == weekday }
    }
}

extension DayPlan {
    var activeSortedWorkouts: [WorkoutTemplate] {
        workouts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortIndex == rhs.sortIndex {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortIndex < rhs.sortIndex
            }
    }
}

enum PlatePresets {
    static func defaultValues(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .lb:
            return [45, 35, 25, 10, 5, 2.5]
        case .kg:
            return [25, 20, 15, 10, 5, 2.5, 1.25]
        }
    }

    static func options(for unit: WeightUnit) -> [PlateOption] {
        defaultValues(for: unit).map {
            PlateOption(value: $0, unit: unit, label: "\($0.prettyWeight) \(unit.rawValue)")
        }
    }
}

extension Double {
    var prettyWeight: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        }
        return String(format: "%.2f", self)
            .replacingOccurrences(of: #"(\.[0-9]*?)0+$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
