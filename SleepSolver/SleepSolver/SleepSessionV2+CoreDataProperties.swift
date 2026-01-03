//
//  SleepSessionV2+CoreDataProperties.swift
//  SleepSolver
//
//  Created by Cade Christensen on 1/30/25.
//

import Foundation
import CoreData

extension SleepSessionV2 {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SleepSessionV2> {
        return NSFetchRequest<SleepSessionV2>(entityName: "SleepSessionV2")
    }

    // MARK: - Primary Key
    @NSManaged public var ownershipDay: Date

    // MARK: - Core Timestamps (UTC)
    @NSManaged public var startDateUTC: Date
    @NSManaged public var endDateUTC: Date

    // MARK: - Duration Metrics
    @NSManaged public var deepDuration: Double
    @NSManaged public var remDuration: Double
    @NSManaged public var totalAwakeTime: Double
    @NSManaged public var totalSleepTime: Double
    @NSManaged public var totalTimeInBed: Double

    // MARK: - Health & Score Metrics
    @NSManaged public var sleepScore: Double
    @NSManaged public var isFinalized: Bool
    @NSManaged public var averageHeartRate: Double
    @NSManaged public var averageHRV: Double
    @NSManaged public var averageSpO2: Double
    @NSManaged public var averageRespiratoryRate: Double
    @NSManaged public var wristTemperature: Double

    // MARK: - Recovery Z-Scores
    @NSManaged public var hrvStatus: Double
    @NSManaged public var rhrStatus: Double
    @NSManaged public var respStatus: Double
    @NSManaged public var spo2Status: Double
    @NSManaged public var temperatureStatus: Double
    
    // MARK: - Recovery Baselines
    @NSManaged public var hrvBaseline: Double
    @NSManaged public var rhrBaseline: Double
    @NSManaged public var respBaseline: Double
    @NSManaged public var spo2Baseline: Double
    @NSManaged public var temperatureBaseline: Double

    // Relationships
    @NSManaged public var sourcePeriods: NSSet?
    @NSManaged public var habits: NSSet?
    @NSManaged public var habitMetrics: DailyHabitMetrics?
    @NSManaged public var wristTemperatures: NSSet?
    @NSManaged public var workouts: NSSet?
    @NSManaged public var manualHabits: NSSet?
}

// MARK: - Generated accessors for sourcePeriods
extension SleepSessionV2 {

    @objc(addSourcePeriodsObject:)
    @NSManaged public func addToSourcePeriods(_ value: SleepPeriod)

    @objc(removeSourcePeriodsObject:)
    @NSManaged public func removeFromSourcePeriods(_ value: SleepPeriod)

    @objc(addSourcePeriods:)
    @NSManaged public func addToSourcePeriods(_ values: NSSet)

    @objc(removeSourcePeriods:)
    @NSManaged public func removeFromSourcePeriods(_ values: NSSet)
}

// MARK: - Generated accessors for habits
extension SleepSessionV2 {

    @objc(addHabitsObject:)
    @NSManaged public func addToHabits(_ value: HabitRecord)

    @objc(removeHabitsObject:)
    @NSManaged public func removeFromHabits(_ value: HabitRecord)

    @objc(addHabits:)
    @NSManaged public func addToHabits(_ values: NSSet)

    @objc(removeHabits:)
    @NSManaged public func removeFromHabits(_ values: NSSet)
}

// MARK: - Generated accessors for wristTemperatures
extension SleepSessionV2 {

    @objc(addWristTemperaturesObject:)
    @NSManaged public func addToWristTemperatures(_ value: WristTemperature)

    @objc(removeWristTemperaturesObject:)
    @NSManaged public func removeFromWristTemperatures(_ value: WristTemperature)

    @objc(addWristTemperatures:)
    @NSManaged public func addToWristTemperatures(_ values: NSSet)

    @objc(removeWristTemperatures:)
    @NSManaged public func removeFromWristTemperatures(_ values: NSSet)
}

// MARK: - Generated accessors for workouts
extension SleepSessionV2 {

    @objc(addWorkoutsObject:)
    @NSManaged public func addToWorkouts(_ value: Workout)

    @objc(removeWorkoutsObject:)
    @NSManaged public func removeFromWorkouts(_ value: Workout)

    @objc(addWorkouts:)
    @NSManaged public func addToWorkouts(_ values: NSSet)

    @objc(removeWorkouts:)
    @NSManaged public func removeFromWorkouts(_ values: NSSet)
}

// MARK: - Generated accessors for manualHabits
extension SleepSessionV2 {

    @objc(addManualHabitsObject:)
    @NSManaged public func addToManualHabits(_ value: HabitRecord)

    @objc(removeManualHabitsObject:)
    @NSManaged public func removeFromManualHabits(_ value: HabitRecord)

    @objc(addManualHabits:)
    @NSManaged public func addToManualHabits(_ values: NSSet)

    @objc(removeManualHabits:)
    @NSManaged public func removeFromManualHabits(_ values: NSSet)
}
