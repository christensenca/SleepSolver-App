//
//  SleepPeriod+CoreDataClass.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import Foundation
import CoreData

@objc(SleepPeriod)
public class SleepPeriod: NSManagedObject {
    
    func calculateOwnershipDay() -> Date {
        // 1. Create a calendar configured with the correct historical timezone.
        let timeZone = TimeZone(identifier: originalTimeZone) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        // 2. Find the calendar day on which the sleep started.
        let daySleepStartedIn = calendar.startOfDay(for: startDateUTC)

        // 3. Find the 6 PM mark for that calendar day.
        guard let sixPM_onStartDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: daySleepStartedIn) else {
            return daySleepStartedIn // Fallback to the start of the day
        }

        // 4. THE SIMPLE RULE:
        // If the sleep started at or after 6 PM, it belongs to the NEXT calendar day's sleep cycle.
        // Otherwise, it belongs to the CURRENT calendar day's sleep cycle.
        if startDateUTC >= sixPM_onStartDate {
            // Belongs to the next day.
            return calendar.date(byAdding: .day, value: 1, to: daySleepStartedIn)!
        } else {
            // Belongs to the current day.
            return daySleepStartedIn
        }
    }
    /// Classify this period as major sleep based on duration and sleep stages
    func classifyMajorSleep() -> Bool {
        // Rule 1: Duration must be greater than 3 hours
        guard duration > 3 * 3600 else { return false }
        
        // Rule 2: Must contain at least one Deep or REM sleep sample
        let samples = samplesArray
        return samples.contains { sample in
            sample.stage == 4 || sample.stage == 5 // Deep or REM sleep
        }
    }
    
    /// Update the major sleep classification and save if changed
    func updateMajorSleepClassification() {
        let newClassification = classifyMajorSleep()
        if isMajorSleep != newClassification {
            isMajorSleep = newClassification
            // Debug logging removed to reduce verbosity
            // print("[SleepPeriod] Updated major sleep classification for \(id): \(newClassification)")
        }
    }
}
