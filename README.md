# LiftLog (iOS 26, Offline, SwiftUI + SwiftData)

Minimal offline weightlifting logger.

## Run
1. Open `/Users/shotbyeissa/Documents/19. Im gonna code shit/Sickazzzz Coding/LiftLog/LiftLog.xcodeproj` in Xcode.
2. Select the `LiftLog` target and an iOS Simulator/device running iOS 26 or later.
3. Build and run.

## Scope
- Offline only.
- No accounts, networking, subscriptions, analytics, or cloud sync.
- Local persistence with SwiftData.

## Data Model Implemented
- `AppConfig`
  - `splitLengthWeeks`
  - `createdAt`
  - `barWeightValue`, `barWeightUnit`
  - `plateCatalog: [PlateOption]`
- `SplitPlan`
  - `weeks: [PlanWeek]`
- `PlanWeek`
  - `weekIndex`
  - `dayPlans: [DayPlan]`
- `DayPlan`
  - `weekday`
  - `label`
  - `workouts: [WorkoutTemplate]`
- `WorkoutTemplate`
  - `id`
  - `name`
  - `weightType`
  - `preferredUnit`
  - `sortIndex`
  - `isArchived`
- `WorkoutSession`
  - `id`
  - `date`
  - `weekIndex`
  - `weekday`
  - `dayLabelSnapshot`
  - `entries: [SessionEntry]`
- `SessionEntry`
  - `workoutTemplateId`
  - `workoutNameSnapshot`
  - `weightTypeSnapshot`
  - `sets: [LoggedSet]`
- `LoggedSet`
  - `setNumber`
  - `reps`
  - `loadValue`, `loadUnit` (dumbbell/machine)
  - `perSidePlates`, `barWeightValueSnapshot`, `barWeightUnitSnapshot`, `computedTotalValue`, `computedTotalUnit` (barbell)
- `PlateOption`
  - `id`
  - `value`
  - `unit`
  - `label`
- `PlateCount`
  - `plateOptionId`
  - `countPerSide`

## UX Included
- First-run setup (split length, week/day labels, barbell defaults + plate catalog)
- Workout Day (week/day selector, ordered workouts, add/rename/delete/reorder)
- Add Workout
- Log Workout (fast set entry + copy last set + barbell plate picker + Done save)
- History (week/day filter, session list, read-only detail)
- Settings (edit split plan, edit barbell defaults, factory reset)
