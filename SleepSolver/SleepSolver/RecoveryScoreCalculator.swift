//
//  RecoveryScoreCalculator.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 5/24/25.
//

import Foundation
import CoreData

// MARK: - Recovery Score Calculation

struct RecoveryBaselines {
    let heartRateBaseline: Double
    let heartRateStdDev: Double
    let hrvBaseline: Double
    let hrvStdDev: Double
    let spO2Baseline: Double
    let spO2StdDev: Double
    let respiratoryRateBaseline: Double
    let respiratoryRateStdDev: Double
    let temperatureBaseline: Double
    let temperatureStdDev: Double
    
    static let defaultBaselines = RecoveryBaselines(
        heartRateBaseline: 0,
        heartRateStdDev: 0,
        hrvBaseline: 0,
        hrvStdDev: 0,
        spO2Baseline: 0,
        spO2StdDev: 0,
        respiratoryRateBaseline: 0,
        respiratoryRateStdDev: 0,
        temperatureBaseline: 0,
        temperatureStdDev: 0
    )
}

class RecoveryScoreCalculator {
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - SleepSessionV2 Support Methods
    
    func calculateAndStoreRecoveryMetrics(for session: SleepSessionV2) {
        let sessionDate = session.ownershipDay
        print("--- [RecoveryCalculator] Starting recovery metrics calculation for \(sessionDate) ---")

        // Step 1: Fetch all historical sessions from the last 90 days.
        let historicalSessions = fetchHistoricalSessions(for: sessionDate)
        print("[RecoveryCalculator] Fetched \(historicalSessions.count) total historical sessions for baseline analysis.")

        // Step 2: Calculate and store z-scores and baselines for each metric independently.
        
        // RHR Z-Score and Baseline
        let (rhrZScore, rhrBaseline) = calculateZScoreAndBaseline(
            metricName: "RHR",
            currentValue: session.averageHeartRate,
            historicalSessions: historicalSessions,
            valueExtractor: { $0.averageHeartRate }
        )
        session.rhrStatus = rhrZScore
        session.rhrBaseline = rhrBaseline

        // HRV Z-Score and Baseline
        let (hrvZScore, hrvBaseline) = calculateZScoreAndBaseline(
            metricName: "HRV",
            currentValue: session.averageHRV,
            historicalSessions: historicalSessions,
            valueExtractor: { $0.averageHRV }
        )
        session.hrvStatus = hrvZScore
        session.hrvBaseline = hrvBaseline

        // Temperature Z-Score and Baseline
        let (tempZScore, tempBaseline) = calculateZScoreAndBaseline(
            metricName: "Wrist Temperature",
            currentValue: session.wristTemperature,
            historicalSessions: historicalSessions,
            valueExtractor: { $0.wristTemperature }
        )
        session.temperatureStatus = tempZScore
        session.temperatureBaseline = tempBaseline

        // SpO2 Z-Score and Baseline
        let (spo2ZScore, spo2Baseline) = calculateZScoreAndBaseline(
            metricName: "SpO2",
            currentValue: session.averageSpO2,
            historicalSessions: historicalSessions,
            valueExtractor: { $0.averageSpO2 }
        )
        session.spo2Status = spo2ZScore
        session.spo2Baseline = spo2Baseline

        // Respiratory Rate Z-Score and Baseline
        let (respZScore, respBaseline) = calculateZScoreAndBaseline(
            metricName: "Respiratory Rate",
            currentValue: session.averageRespiratoryRate,
            historicalSessions: historicalSessions,
            valueExtractor: { $0.averageRespiratoryRate }
        )
        session.respStatus = respZScore
        session.respBaseline = respBaseline
        
        print("--- [RecoveryCalculator] Calculation ENDED ---")
    }

    private func fetchHistoricalSessions(for date: Date) -> [SleepSessionV2] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: date)
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) else {
            return []
        }

        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay < %@", startDate as NSDate, endDate as NSDate)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching historical sessions: \(error)")
            return []
        }
    }

    private func calculateZScoreAndBaseline(metricName: String, currentValue: Double, historicalSessions: [SleepSessionV2], valueExtractor: (SleepSessionV2) -> Double) -> (zScore: Double, baseline: Double) {
        // Ensure the current session has a valid value for this metric.
        guard currentValue > 0 else {
            print("[RecoveryCalculator] \(metricName): SKIPPED - No current value.")
            return (-100.0, -100.0) // Sentinel values indicating "not calculated"
        }

        // Filter historical sessions to only include those with a valid value for this metric.
        let validHistoricalValues = historicalSessions.map(valueExtractor).filter { $0 > 0 }

        // Check if we have enough data to form a reliable baseline.
        guard validHistoricalValues.count >= 7 else {
            print("[RecoveryCalculator] \(metricName): FAILED - Not enough baseline data (\(validHistoricalValues.count) < 7)." )
            return (-100.0, -100.0) // Sentinel values indicating "not calculated"
        }

        // Calculate baseline and standard deviation.
        let baseline = validHistoricalValues.average
        let stdDev = validHistoricalValues.stdDev
        
        print("[RecoveryCalculator] \(metricName): PASSED - Baseline: \(baseline), StdDev: \(stdDev) from \(validHistoricalValues.count) sessions.")

        // Calculate and return the pure statistical z-score (no directional adjustment)
        guard stdDev > 0 else { return (0.0, baseline) }
        let zScore = (currentValue - baseline) / stdDev
        
        return (zScore, baseline)
    }
    
    // MARK: - Helper Methods for UI
    
    /// Returns the count of sessions with valid health data for baseline calculation
    func getAvailableSessionsCount(for date: Date) -> Int {
        let historicalSessions = fetchHistoricalSessions(for: date)
        
        // Count sessions that have at least one valid health metric (> 0)
        let validSessions = historicalSessions.filter { session in
            return session.averageHRV > 0 || 
                   session.averageHeartRate > 0 || 
                   session.averageSpO2 > 0 || 
                   session.averageRespiratoryRate > 0 ||
                   session.wristTemperature > 0
        }
        
        return validSessions.count
    }

    private func calculateZScoreForMetric(metricName: String, currentValue: Double, historicalSessions: [SleepSessionV2], valueExtractor: (SleepSessionV2) -> Double, isHigherBetter: Bool) -> Double {
        let (zScore, _) = calculateZScoreAndBaseline(metricName: metricName, currentValue: currentValue, historicalSessions: historicalSessions, valueExtractor: valueExtractor)
        return zScore
    }
    
    private func calculateFlexibleZScoreForMetric(metricName: String, currentValue: Double, historicalSessions: [SleepSessionV2], valueExtractor: (SleepSessionV2) -> Double, penalizeDirection: PenalizeDirection) -> Double {
        let (zScore, _) = calculateZScoreAndBaseline(metricName: metricName, currentValue: currentValue, historicalSessions: historicalSessions, valueExtractor: valueExtractor)
        return zScore
    }

    private func isSessionValid(_ session: SleepSessionV2) -> Bool {
        return session.averageHeartRate > 0 &&
               session.averageHRV > 0 &&
               session.averageSpO2 > 0 &&
               session.averageRespiratoryRate > 0
    }

    private func isBaselinesValid(_ baselines: RecoveryBaselines, sessionCount: Int) -> Bool {
        return sessionCount >= 7
    }

    func calculateBaselinesWithValidationV2(for date: Date) -> (baselines: RecoveryBaselines, sessionCount: Int) {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: date)
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) else {
            return (RecoveryBaselines.defaultBaselines, 0)
        }

        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay < %@", startDate as NSDate, endDate as NSDate)
        
        do {
            let sessions = try context.fetch(request)
            let validSessions = sessions.filter { isSessionValid($0) }
            
            if validSessions.count < 7 {
                return (RecoveryBaselines.defaultBaselines, validSessions.count)
            }
            
            return (processBaselineSessionsV2(validSessions), validSessions.count)
        } catch {
            print("Error fetching baseline sessions: \(error)")
            return (RecoveryBaselines.defaultBaselines, 0)
        }
    }

    private func processBaselineSessionsV2(_ sessions: [SleepSessionV2]) -> RecoveryBaselines {
        let heartRates = sessions.map { $0.averageHeartRate }
        let hrvs = sessions.map { $0.averageHRV }
        let spO2s = sessions.map { $0.averageSpO2 }
        let respRates = sessions.map { $0.averageRespiratoryRate }
        let temperatures = sessions.filter { $0.wristTemperature > 0 }.map { $0.wristTemperature }

        return RecoveryBaselines(
            heartRateBaseline: heartRates.average,
            heartRateStdDev: heartRates.stdDev,
            hrvBaseline: hrvs.average,
            hrvStdDev: hrvs.stdDev,
            spO2Baseline: spO2s.average,
            spO2StdDev: spO2s.stdDev,
            respiratoryRateBaseline: respRates.average,
            respiratoryRateStdDev: respRates.stdDev,
            temperatureBaseline: temperatures.average,
            temperatureStdDev: temperatures.stdDev
        )
    }

    private func calculateMetricScore(current: Double, baseline: Double, stdDev: Double, maxPoints: Double, isHigherBetter: Bool, k: Double) -> Double {
        guard stdDev > 0 else { return maxPoints / 2 }
        
        let zScore = (current - baseline) / stdDev
        let effectiveZ = isHigherBetter ? zScore : -zScore
        
        // Sigmoid-like function to map z-score to a score
        let score = maxPoints / (1 + exp(-k * effectiveZ))
        return score
    }

    enum PenalizeDirection {
        case aboveBaseline
        case belowBaseline
    }

    private func calculateFlexibleMetricScore(current: Double, baseline: Double, stdDev: Double, maxPoints: Double, penalizeDirection: PenalizeDirection, k: Double) -> Double {
        guard stdDev > 0 else { return maxPoints } // If no deviation, assume perfect score
        
        let deviation = current - baseline
        
        let shouldPenalize = (penalizeDirection == .aboveBaseline && deviation > 0) || (penalizeDirection == .belowBaseline && deviation < 0)
        
        if !shouldPenalize {
            return maxPoints // No penalty if deviation is in the "good" direction
        }
        
        let zScore = abs(deviation) / stdDev
        
        // An exponential decay function for penalty
        let penalty = maxPoints * exp(-k * zScore)
        return penalty
    }
    
    // MARK: - Metric Status Calculation
    
    private func determineMetricStatus(current: Double, baseline: Double, stdDev: Double, isHigherBetter: Bool) -> String {
        guard stdDev > 0 else { return "good" }

        let zScore = (current - baseline) / stdDev
        let thresholdOptimal: Double = 0.5
        let thresholdGood: Double = 1.5

        if isHigherBetter {
            if zScore >= thresholdOptimal { return "optimal" }
            if zScore > -thresholdGood { return "good" }
            return "attention"
        } else { // Lower is better
            if zScore <= -thresholdOptimal { return "optimal" }
            if zScore < thresholdGood { return "good" }
            return "attention"
        }
    }

    private func determineFlexibleMetricStatus(current: Double, baseline: Double, stdDev: Double, penalizeDirection: PenalizeDirection) -> String {
        guard stdDev > 0 else { return "good" }

        let deviation = current - baseline
        let zScore = abs(deviation) / stdDev
        let thresholdOptimal: Double = 0.5
        let thresholdGood: Double = 1.5

        let shouldPenalize = (penalizeDirection == .aboveBaseline && deviation > 0) || (penalizeDirection == .belowBaseline && deviation < 0)

        if !shouldPenalize {
            // If the deviation is in the good direction, it's at least good.
            // We can consider it optimal if it's significantly better.
            if zScore >= thresholdOptimal {
                return "optimal"
            } else {
                return "good"
            }
        }

        // If we are here, it means we should penalize.
        if zScore >= thresholdGood {
            return "attention"
        } else {
            return "good"
        }
    }
}

// MARK: - Array Extensions for Math

extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
    
    var stdDev: Double {
        guard count > 1 else { return 0 }
        let mean = average
        let sumOfSquaredDiffs = self.map { pow($0 - mean, 2.0) }.reduce(0, +)
        return sqrt(sumOfSquaredDiffs / Double(count - 1))
    }
}
