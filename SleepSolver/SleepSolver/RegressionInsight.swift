import Foundation
import SwiftUI

// New insight structure for regression-based analysis
struct RegressionInsight: Identifiable, Hashable {
    let id = UUID()
    let healthMetricName: String
    let healthMetricIcon: String
    let sleepMetricName: String
    let sleepMetricIcon: String

    // Regression results
    let coefficient: Double           // β coefficient (impact per unit)
    let absoluteImpact: Double        // Real-world impact (minutes/hours/points)
    let pValue: Double               // Statistical significance
    let confidenceInterval: (lower: Double, upper: Double)

    // UI display properties
    let impactDescription: String     // User-friendly description
    let confidenceLevel: ConfidenceLevel
    let sampleSize: Int

    // Keep existing drill-down functionality
    let binAnalysisResult: BinAnalysisResult? // For bar charts

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RegressionInsight, rhs: RegressionInsight) -> Bool {
        lhs.id == rhs.id
    }
}

// Confidence level based on statistical significance
enum ConfidenceLevel: String, CaseIterable {
    case strong = "Strong"
    case moderate = "Moderate"
    case weak = "Weak"
    case uncertain = "Uncertain"

    var displayName: String {
        return self.rawValue
    }

    var color: Color {
        switch self {
        case .strong: return .green
        case .moderate: return .yellow
        case .weak: return .orange
        case .uncertain: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .strong: return "🟢"
        case .moderate: return "🟡"
        case .weak: return "🟠"
        case .uncertain: return "⚪"
        }
    }

    static func fromPValue(_ pValue: Double) -> ConfidenceLevel {
        switch pValue {
        case ..<0.01: return .strong
        case ..<0.05: return .moderate
        case ..<0.10: return .weak
        default: return .uncertain
        }
    }
}

// Helper for generating user-friendly impact descriptions
struct ImpactDescriptionGenerator {
    static func generateDescription(
        coefficient: Double,
        healthMetric: String,
        sleepMetric: CorrelationMetric,
        typicalChange: Double = 1.0
    ) -> String {
        let impact = coefficient * typicalChange

        switch sleepMetric {
        case .sleepScore:
            let direction = impact >= 0 ? "higher" : "lower"
            return String(format: "%.1f points %@", abs(impact), direction)

        case .sleepDuration:
            let direction = impact >= 0 ? "more" : "less"
            if abs(impact) >= 1.0 {
                return String(format: "%.1f hours %@", abs(impact), direction)
            } else {
                let minutes = abs(impact) * 60
                return String(format: "%.0f min %@", minutes, direction)
            }

        case .totalAwakeTime:
            let direction = impact >= 0 ? "more" : "less"
            if abs(impact) >= 1.0 {
                return String(format: "%.1f hours %@", abs(impact), direction)
            } else {
                let minutes = abs(impact) * 60
                return String(format: "%.0f min %@", minutes, direction)
            }

        case .deepSleep, .remSleep:
            let direction = impact >= 0 ? "more" : "less"
            if abs(impact) >= 1.0 {
                return String(format: "%.1f hours %@", abs(impact), direction)
            } else {
                let minutes = abs(impact) * 60
                return String(format: "%.0f min %@", minutes, direction)
            }

        case .hrv:
            let direction = impact >= 0 ? "higher" : "lower"
            return String(format: "%.1f ms %@", abs(impact), direction)

        case .heartRate:
            let direction = impact >= 0 ? "higher" : "lower"
            return String(format: "%.1f bpm %@", abs(impact), direction)
        }
    }

    static func getTypicalValueChange(for healthMetric: String) -> Double {
        switch healthMetric {
        case "Exercise Time":
            return 60.0 // 1 hour of exercise
        case "Steps":
            return 100.0 // 100 steps
        case "Time in Daylight":
            return 60.0 // 1 hour of daylight
        default:
            return 1.0 // Default scaling
        }
    }

    static func generateFullDescription(
        insight: RegressionInsight,
        healthMetric: String
    ) -> String {
        let typicalChange = getTypicalValueChange(for: healthMetric)
        let unitDescription = getUnitDescription(for: healthMetric, change: typicalChange)

        return "\(insight.impactDescription) per \(unitDescription)"
    }

    private static func getUnitDescription(for healthMetric: String, change: Double) -> String {
        switch healthMetric {
        case "Exercise Time":
            return "hour of exercise"
        case "Steps":
            return "1,000 steps"
        case "Time in Daylight":
            return "hour in daylight"
        default:
            return "unit"
        }
    }
}
