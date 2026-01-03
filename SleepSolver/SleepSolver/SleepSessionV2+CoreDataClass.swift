//
//  SleepSessionV2+CoreDataClass.swift
//  SleepSolver
//
//  Created by Cade Christensen on 1/30/25.
//

import Foundation
import CoreData
import HealthKit

@objc(SleepSessionV2)
public class SleepSessionV2: NSManagedObject {
    
    // MARK: - Properties
    
    // MARK: - Computed Properties
    
    /// Returns the primary sleep period (the longest one) for this session
    var primarySleepPeriod: SleepPeriod? {
        guard let periods = sourcePeriods?.allObjects as? [SleepPeriod] else { return nil }
        return periods.filter { $0.isMajorSleep }.max { $0.duration < $1.duration }
    }
    
    /// Returns all nap periods linked to this session
    var napPeriods: [SleepPeriod] {
        guard let periods = sourcePeriods?.allObjects as? [SleepPeriod] else { return [] }
        return periods.filter { !$0.isMajorSleep }.sorted { $0.startDateUTC < $1.startDateUTC }
    }
    
    /// Returns the total duration including all linked periods (primary + naps)
    var totalDurationIncludingNaps: TimeInterval {
        guard let periods = sourcePeriods?.allObjects as? [SleepPeriod] else { return totalTimeInBed }
        return periods.reduce(0) { $0 + $1.duration }
    }
    
    /// Returns the number of linked sleep periods
    var linkedPeriodsCount: Int {
        return sourcePeriods?.count ?? 0
    }
    
    // MARK: - Sleep Score Calculation
    
    /// Calculates the total sleep score with correct point allocations
    /// - Duration: 60 points max
    /// - REM sleep: 15 points max
    /// - Deep sleep: 15 points max
    /// - Awake frequency: 10 points max
    /// Total: 100 points max
    func calculateSleepScore() -> Double {
        let durationScore = calculateDurationScore()     // 0-60 points
        let remScore = calculateREMScore()               // 0-15 points
        let deepScore = calculateDeepScore()             // 0-15 points
        let awakeScore = calculateAwakeScore()           // 0-10 points
        
        let totalScore = durationScore + remScore + deepScore + awakeScore
        return totalScore
    }
    
    /// Calculate duration score (0-60 points)
    /// Based on actual sleep time vs user's sleep need
    func calculateDurationScore() -> Double {
        let userSleepNeed = UserDefaults.standard.double(forKey: "userSleepNeed")
        
        // Default to 8 hours if not set
        let targetHours = userSleepNeed > 0 ? userSleepNeed : 8.0
        let targetSeconds = targetHours * 3600.0
        
        // Calculate percentage of sleep need met, capped at 100%
        let percentage = min(1.0, totalSleepTime / targetSeconds)
        return percentage * 60.0 // Max 60 points
    }
    
    /// Calculate REM sleep score (0-15 points)
    /// Based on assumption that 1/4 of sleep need should be REM sleep
    func calculateREMScore() -> Double {
        let userSleepNeed = UserDefaults.standard.double(forKey: "userSleepNeed")
        
        // Default to 8 hours if not set
        let targetHours = userSleepNeed > 0 ? userSleepNeed : 8.0
        let targetREMSeconds = (targetHours / 4.0) * 3600.0 // 1/4 of sleep need
        
        // Calculate percentage of target REM achieved, capped at 100%
        let percentage = min(1.0, remDuration / targetREMSeconds)
        return percentage * 15.0 // Max 15 points
    }
    
    /// Calculate deep sleep score (0-15 points)
    /// Based on assumption that 1/4 of sleep need should be deep sleep
    func calculateDeepScore() -> Double {
        let userSleepNeed = UserDefaults.standard.double(forKey: "userSleepNeed")
        
        // Default to 8 hours if not set
        let targetHours = userSleepNeed > 0 ? userSleepNeed : 8.0
        let targetDeepSeconds = (targetHours / 4.0) * 3600.0 // 1/4 of sleep need
        
        // Calculate percentage of target deep sleep achieved, capped at 100%
        let percentage = min(1.0, deepDuration / targetDeepSeconds)
        return percentage * 15.0 // Max 15 points
    }
    
    /// Calculate awake score based on number of wake-ups and longest awake period (0-10 points)
    /// Fewer wake-ups = better score, with additional penalty for long awake periods
    func calculateAwakeScore() -> Double {
        // Count the number of awake periods from samples
        let awakeCount = countAwakePeriods()
        let longestAwakeDuration = findLongestAwakePeriod()
        
        // Base scoring: 0-2 wake-ups = 10 points, then decrease
        var score: Double
        if awakeCount <= 2 {
            score = 10.0
        } else if awakeCount <= 7 {
            // Decrease by 2 points for each wake-up beyond 2
            score = max(0, 10.0 - 2.0 * Double(awakeCount - 2))
        } else {
            score = 0.0
        }
        
        // Additional penalty: if longest awake period > 20 minutes, subtract 5 points
        if longestAwakeDuration > 20 * 60 { // 20 minutes in seconds
            score -= 5.0
        }
        
        return max(0, score) // Ensure score doesn't go below 0
    }
    
    /// Count the number of distinct awake periods from sleep samples
    /// Only counts awake periods longer than 2 minutes
    func countAwakePeriods() -> Int {
        guard let primaryPeriod = primarySleepPeriod else { return 0 }
        
        let awakeSamples = Array(primaryPeriod.samples).filter { $0.stage == 2 } // Awake stage
        var awakeCount = 0
        
        for sample in awakeSamples {
            let awakeDuration = sample.endDateUTC.timeIntervalSince(sample.startDateUTC)
            if awakeDuration >= 120 { // Only count if > 2 minutes (120 seconds)
                awakeCount += 1
            }
        }
        
        return awakeCount
    }
    
    /// Find the duration of the longest awake period during sleep
    private func findLongestAwakePeriod() -> TimeInterval {
        guard let primaryPeriod = primarySleepPeriod else { return 0 }
        
        let samples = Array(primaryPeriod.samples).sorted { $0.startDateUTC < $1.startDateUTC }
        var longestAwakeDuration: TimeInterval = 0
        var currentAwakeStart: Date?
        
        for sample in samples {
            if sample.stage == 2 { // Awake stage
                if currentAwakeStart == nil {
                    currentAwakeStart = sample.startDateUTC
                }
            } else {
                // End of awake period
                if let awakeStart = currentAwakeStart {
                    let awakeDuration = sample.startDateUTC.timeIntervalSince(awakeStart)
                    longestAwakeDuration = max(longestAwakeDuration, awakeDuration)
                    currentAwakeStart = nil
                }
            }
        }
        
        // Handle case where sleep ends with an awake period
        if let awakeStart = currentAwakeStart,
           let lastSample = samples.last {
            let awakeDuration = lastSample.endDateUTC.timeIntervalSince(awakeStart)
            longestAwakeDuration = max(longestAwakeDuration, awakeDuration)
        }
        
        return longestAwakeDuration
    }

    // MARK: - Helper Methods
    
    /// Updates the session's metrics based on the primary sleep period
    func updateFromPrimarySleepPeriod(_ period: SleepPeriod) {
        startDateUTC = period.startDateUTC
        endDateUTC = period.endDateUTC
        totalTimeInBed = period.duration
        
        // Calculate sleep stages from samples
        if !period.samples.isEmpty {
            let samples = Array(period.samples)
            let deepSamples = samples.filter { $0.stage == 4 } // Deep sleep
            let remSamples = samples.filter { $0.stage == 5 }  // REM sleep
            let awakeSamples = samples.filter { $0.stage == 2 } // Awake
            
            deepDuration = deepSamples.reduce(0) { $0 + ($1.endDateUTC.timeIntervalSince($1.startDateUTC)) }
            remDuration = remSamples.reduce(0) { $0 + ($1.endDateUTC.timeIntervalSince($1.startDateUTC)) }
            totalAwakeTime = awakeSamples.reduce(0) { $0 + ($1.endDateUTC.timeIntervalSince($1.startDateUTC)) }
            totalSleepTime = totalTimeInBed - totalAwakeTime
        } else {
            // No samples available - use zeros instead of estimates
            totalSleepTime = 0.0
            totalAwakeTime = 0.0
            deepDuration = 0.0
            remDuration = 0.0
        }
        
        // Calculate and update sleep score
        sleepScore = calculateSleepScore()
    }
    
    /// Links a sleep period to this session
    func linkSleepPeriod(_ period: SleepPeriod) {
        addToSourcePeriods(period)
        period.isResolved = true
    }
    
    /// Unlinks a sleep period from this session
    func unlinkSleepPeriod(_ period: SleepPeriod) {
        removeFromSourcePeriods(period)
        period.isResolved = false
    }
    
}

// MARK: - Identifiable
extension SleepSessionV2: Identifiable {
    public var id: Date { ownershipDay }
}

extension SleepSessionV2 {
    // Your custom properties and methods here
    var debugIdentifier: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return "Session for \(dateFormatter.string(from: ownershipDay))"
    }
}
