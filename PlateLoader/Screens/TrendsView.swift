import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    @Query(sort: \WorkoutTemplate.name)
    private var templates: [WorkoutTemplate]

    @Query(sort: \WorkoutSession.date)
    private var sessions: [WorkoutSession]

    @State private var metric: TrendMetric = .weight

    var body: some View {
        VStack(spacing: 12) {
            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if trendSeries.isEmpty {
                ContentUnavailableView(
                    "No Workouts",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Add workouts first to see trend cards.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(trendSeries) { series in
                            trendCard(for: series)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Trends")
    }

    private func trendCard(for series: WorkoutTrendSeries) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.name)
                        .font(.headline)
                    Text(series.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(series.points.count)x")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }

            if series.points.isEmpty {
                Text("No logged sessions yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if metric == .weight && series.weightPoints.isEmpty {
                    Text("No weight values logged yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        if metric == .weight {
                            ForEach(series.weightPoints) { point in
                                LineMark(
                                    x: .value("Workout #", point.sequence),
                                    y: .value("Peak Weight", point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.blue)

                                PointMark(
                                    x: .value("Workout #", point.sequence),
                                    y: .value("Peak Weight", point.value)
                                )
                                .foregroundStyle(.blue)
                            }
                        } else {
                            ForEach(series.points) { point in
                                LineMark(
                                    x: .value("Workout #", point.sequence),
                                    y: .value("Peak Reps", point.repsPeak)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(.green)

                                PointMark(
                                    x: .value("Workout #", point.sequence),
                                    y: .value("Peak Reps", point.repsPeak)
                                )
                                .foregroundStyle(.green)
                            }
                        }
                    }
                    .frame(height: 170)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6))
                    }
                }

                HStack {
                    Text(metric == .weight ? "Best Weight" : "Best Reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(metricSummary(for: series))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func metricSummary(for series: WorkoutTrendSeries) -> String {
        if metric == .weight {
            guard let best = series.bestWeight else {
                return "No data"
            }

            if let unit = series.weightUnitLabel {
                return "\(best.prettyWeight) \(unit.rawValue)"
            }
            return best.prettyWeight
        }

        return "\(series.bestReps)"
    }

    private var trendSeries: [WorkoutTrendSeries] {
        let activeTemplates = templates.filter { !$0.isArchived }
        guard !activeTemplates.isEmpty else { return [] }

        var definitionsByKey: [String: TrendDefinition] = [:]

        for template in activeTemplates {
            let normalizedName = normalizeName(template.name)
            guard !normalizedName.isEmpty else { continue }

            let unitKey = template.weightType.usesPlatePicker ? "plate" : template.preferredUnit.rawValue
            let key = "\(normalizedName)|\(template.weightType.rawValue)|\(unitKey)"

            if var existing = definitionsByKey[key] {
                existing.templateIDs.insert(template.id)
                definitionsByKey[key] = existing
            } else {
                definitionsByKey[key] = TrendDefinition(
                    key: key,
                    displayName: template.name,
                    normalizedName: normalizedName,
                    weightType: template.weightType,
                    preferredUnit: template.preferredUnit,
                    templateIDs: [template.id]
                )
            }
        }

        let sortedSessions = sessions.sorted { $0.date < $1.date }

        return definitionsByKey.values.map { definition in
            var points: [TrendPoint] = []

            for session in sortedSessions {
                let matchingEntries = session.entries.filter { entry in
                    if definition.templateIDs.contains(entry.workoutTemplateId) {
                        return true
                    }

                    return entry.weightTypeSnapshot == definition.weightType
                        && normalizeName(entry.workoutNameSnapshot) == definition.normalizedName
                }

                guard !matchingEntries.isEmpty else { continue }

                var peakWeight: Double?
                var peakWeightUnit: WeightUnit?
                var peakReps = 0

                for entry in matchingEntries {
                    for set in entry.sets {
                        peakReps = max(peakReps, max(0, set.reps))

                        let candidateWeight: Double?
                        let candidateUnit: WeightUnit?

                        if definition.weightType.usesPlatePicker {
                            candidateWeight = set.computedTotalValue.map { max(0, $0) }
                            candidateUnit = set.computedTotalUnit
                        } else {
                            candidateWeight = set.loadValue.map { max(0, $0) }
                            candidateUnit = set.loadUnit
                        }

                        if let value = candidateWeight {
                            if let currentPeak = peakWeight {
                                if value > currentPeak {
                                    peakWeight = value
                                    peakWeightUnit = candidateUnit
                                }
                            } else {
                                peakWeight = value
                                peakWeightUnit = candidateUnit
                            }
                        }
                    }
                }

                points.append(
                    TrendPoint(
                        sequence: points.count + 1,
                        date: session.date,
                        weightPeak: peakWeight,
                        weightUnit: peakWeightUnit,
                        repsPeak: peakReps
                    )
                )
            }

            return WorkoutTrendSeries(
                id: definition.key,
                name: definition.displayName,
                weightType: definition.weightType,
                preferredUnit: definition.preferredUnit,
                points: points
            )
        }
        .sorted {
            let nameSort = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameSort == .orderedSame {
                return $0.weightType.rawValue < $1.weightType.rawValue
            }
            return nameSort == .orderedAscending
        }
    }

    private func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case weight
    case reps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        }
    }
}

private struct TrendDefinition {
    var key: String
    var displayName: String
    var normalizedName: String
    var weightType: WeightType
    var preferredUnit: WeightUnit
    var templateIDs: Set<UUID>
}

private struct WorkoutTrendSeries: Identifiable {
    let id: String
    let name: String
    let weightType: WeightType
    let preferredUnit: WeightUnit
    let points: [TrendPoint]

    var subtitle: String {
        if weightType.usesPlatePicker {
            return weightType.title
        }
        return "\(weightType.title) • \(preferredUnit.title)"
    }

    var weightPoints: [TrendWeightPoint] {
        points.compactMap { point in
            guard let value = point.weightPeak else { return nil }
            return TrendWeightPoint(sequence: point.sequence, value: value, unit: point.weightUnit)
        }
    }

    var bestWeight: Double? {
        weightPoints.map(\.value).max()
    }

    var bestReps: Int {
        points.map(\.repsPeak).max() ?? 0
    }

    var weightUnitLabel: WeightUnit? {
        let seen = weightPoints.compactMap(\.unit)
        return seen.first ?? preferredUnit
    }
}

private struct TrendPoint: Identifiable {
    let sequence: Int
    let date: Date
    let weightPeak: Double?
    let weightUnit: WeightUnit?
    let repsPeak: Int

    var id: Int { sequence }
}

private struct TrendWeightPoint: Identifiable {
    let sequence: Int
    let value: Double
    let unit: WeightUnit?

    var id: Int { sequence }
}
