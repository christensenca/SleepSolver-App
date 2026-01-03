//
//  SleepAnalysisEngine.swift
//  SleepSolver
//
//  Created by Cade Christensen on 1/30/25.
//

import Foundation
import CoreData

class SleepAnalysisEngine {
    private var context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Processes all unresolved sleep periods in the database.
    func runAnalysis() {
        let request: NSFetchRequest<SleepPeriod> = SleepPeriod.fetchRequest()
        request.predicate = NSPredicate(format: "isResolved == NO")
        
        do {
            let unresolvedPeriods = try context.fetch(request)
            if unresolvedPeriods.isEmpty {
                return
            }
            
            print("[SleepAnalysisEngine] Found \(unresolvedPeriods.count) unresolved sleep periods to process.")
            // Group periods by their calculated ownership day
            let periodsByDay = Dictionary(grouping: unresolvedPeriods, by: { $0.calculateOwnershipDay() })
            
            for (day, periods) in periodsByDay {
                if periods.contains(where: { $0.isMajorSleep }) {
                    // Process normally - has major sleep period
                    runAnalysis(for: periods, on: day)
                } else {
                    // Handle minor sleep periods (naps) - try to link to existing session
                    handleMinorSleepPeriods(periods, for: day)
                }
            }
            
            print("[SleepAnalysisEngine] Finished processing sleep periods.")
        } catch {
            print("Failed to fetch unresolved sleep periods: \(error)")
        }
    }
    
    /// Handles minor sleep periods (naps) by attempting to link them to existing sessions
    private func handleMinorSleepPeriods(_ periods: [SleepPeriod], for day: Date) {
        // Try to find an existing session for this day
        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.predicate = NSPredicate(format: "ownershipDay == %@", day as NSDate)
        request.fetchLimit = 1
        
        do {
            if let existingSession = try context.fetch(request).first {
                print("[SleepAnalysisEngine] Found existing session for \(day), linking \(periods.count) minor sleep periods")
                
                // Link all periods to the existing session
                for period in periods {
                    existingSession.linkSleepPeriod(period)
                    period.isResolved = true
                }
                
                // Update session metrics if needed (recalculate with new periods)
                // Note: We don't update the primary period since these are minor periods
                
                // Save the updated session
                try context.save()
                print("[SleepAnalysisEngine] Successfully linked \(periods.count) minor periods to existing session")
                
            } else {
                print("[SleepAnalysisEngine] No existing session found for \(day), marking \(periods.count) minor periods as resolved to prevent reprocessing")
                
                // Mark as resolved to prevent infinite reprocessing
                for period in periods {
                    period.isResolved = true
                }
                
                try context.save()
            }
            
        } catch {
            print("[SleepAnalysisEngine] Error handling minor sleep periods: \(error)")
            
            // Mark as resolved even on error to prevent infinite loops
            for period in periods {
                period.isResolved = true
            }
            
            do {
                try context.save()
            } catch {
                print("[SleepAnalysisEngine] Failed to save after error handling: \(error)")
            }
        }
    }

    /// Analyzes a given set of sleep periods for a specific day to generate a SleepSessionV2.
    private func runAnalysis(for periods: [SleepPeriod], on day: Date) {
        guard !periods.isEmpty else {
            print("No periods provided for analysis on \(day).")
            return
        }
        
        // Find the longest sleep period to serve as the main period for the session
        guard let mainPeriod = periods.max(by: { $0.duration < $1.duration }) else {
            print("Could not determine the main sleep period.")
            return
        }
        
        // Create or fetch the sleep session for the given day
        let session = findOrCreateSession(for: day)
        
        // Link all periods to the session and update session metrics
        for period in periods {
            session.linkSleepPeriod(period)
        }
        
        session.updateFromPrimarySleepPeriod(mainPeriod)
        
        // Save the session with sleep data first
        context.performAndWait {
            do {
                try context.save()
                print("[SleepAnalysisEngine] Successfully saved session with sleep data for \(day)")
            } catch {
                print("Failed to save context after sleep data: \(error)")
                return
            }
        }
        
        // Use coordinated health data linking to prevent race conditions
        Task { @MainActor in
            await SleepSessionDataCoordinator.shared.linkAllHealthDataToSession(session, context: self.context)
            print("[SleepAnalysisEngine] Completed coordinated health data linking for \(day)")
        }
        
        // Mark all processed periods as resolved and save initial session
        periods.forEach { $0.isResolved = true }
        
        // Save the context with the session (habit metrics will be added async)
        do {
            try context.save()
            print("[SleepAnalysisEngine] Successfully saved initial session for \(day)")
        } catch {
            print("Failed to save context after sleep analysis: \(error)")
        }
    }
    
    private func linkWristTemperatureSamples(to session: SleepSessionV2, for day: Date) {
        let request: NSFetchRequest<WristTemperature> = WristTemperature.fetchRequest()
        
        // Use a UTC calendar for timezone-agnostic calculations
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        // Create a -6hr/+18hr window around the ownership day for robust matching
        guard let windowStart = calendar.date(byAdding: .hour, value: -6, to: day),
              let windowEnd = calendar.date(byAdding: .hour, value: 18, to: day) else {
            print("Could not calculate the time window for wrist temperature fetching.")
            return
        }
        
        // Fetch unresolved temperature samples that fall within the session's time window
        request.predicate = NSPredicate(format: "isResolved == NO AND date >= %@ AND date <= %@", windowStart as NSDate, windowEnd as NSDate)
        
        do {
            let unresolvedTemps = try context.fetch(request)
            if unresolvedTemps.isEmpty {
                // It's possible no temperature data is available for this session, which is not an error.
                return
            }
            
            // HealthKit generally provides one basal body temperature sample per major sleep session.
            // We will link all that fall in the window, but only the first one will set the session's primary value.
            for tempSample in unresolvedTemps {
                session.addToWristTemperatures(tempSample)
                tempSample.isResolved = true
            }
            
            // Set the session's wrist temperature to the first sample found.
            // This aligns with the expectation of a single value per major sleep event.
            if let firstTemp = unresolvedTemps.first {
                session.wristTemperature = firstTemp.value
            }
            
        } catch {
            print("Failed to fetch or link wrist temperature samples: \(error)")
        }
    }
    
    private func findOrCreateSession(for day: Date) -> SleepSessionV2 {
        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.predicate = NSPredicate(format: "ownershipDay == %@", day as NSDate)
        request.fetchLimit = 1
        
        do {
            if let existingSession = try context.fetch(request).first {
                return existingSession
            }
        } catch {
            print("Failed to fetch or create sleep session: \(error)")
        }
        
        // If no existing session, create a new one
        let newSession = SleepSessionV2(context: context)
        newSession.ownershipDay = day
        newSession.isFinalized = false // Mark as not finalized initially
        newSession.sleepScore = 0
        newSession.deepDuration = 0.0
        newSession.remDuration = 0.0
        newSession.totalAwakeTime = 0.0
        newSession.totalSleepTime = 0.0
        newSession.totalTimeInBed = 0.0
        newSession.startDateUTC = day
        newSession.endDateUTC = day
        
        return newSession
    }
    
    /// Asynchronously fetches HealthKit habit data for the 24 hours preceding the session's ownershipDay and links it to the session
    private func fetchAndLinkHabitMetrics(for session: SleepSessionV2, completion: @escaping (Bool) -> Void) {
        // Calculate the 24-hour window preceding ownershipDay
        // Since ownershipDay is already the midnight of local timezone converted to UTC,
        // we just need to query from ownershipDay - 24h to ownershipDay
        let endDate = session.ownershipDay
        guard let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: endDate) else {
            print("Failed to calculate start date for habit metrics fetching")
            completion(false)
            return
        }
        
        print("[SleepAnalysisEngine] Fetching habit metrics from \(startDate) to \(endDate) for session \(session.ownershipDay)")
        
        // Use the improved async completion handler pattern from HealthKitManager
        HealthKitManager.shared.fetchHabitMetrics(startDate: startDate, endDate: endDate) { [weak self] habitMetrics, error in
            guard let self = self else {
                print("[SleepAnalysisEngine] Self was deallocated during habit metrics fetch")
                completion(false)
                return
            }
            
            if let error = error {
                print("[SleepAnalysisEngine] Failed to fetch habit metrics: \(error)")
                completion(false)
                return
            }
            
            guard let habitMetrics = habitMetrics else {
                print("[SleepAnalysisEngine] No habit metrics returned (nil)")
                completion(false)
                return
            }
            
            print("[SleepAnalysisEngine] Successfully fetched habit metrics - Steps: \(habitMetrics.steps), Exercise: \(habitMetrics.exerciseTime), Daylight: \(habitMetrics.timeInDaylight)")
            
            // Create or update DailyHabitMetrics for this day on the CoreData queue
            self.context.perform {
                do {
                    let dailyHabitMetrics = self.findOrCreateDailyHabitMetrics(for: session.ownershipDay)
                    
                    // Set the habit data
                    dailyHabitMetrics.steps = habitMetrics.steps
                    dailyHabitMetrics.exerciseTime = habitMetrics.exerciseTime
                    dailyHabitMetrics.timeinDaylight = habitMetrics.timeInDaylight
                    dailyHabitMetrics.date = session.ownershipDay
                    
                    // Link the habit metrics to the session bidirectionally
                    dailyHabitMetrics.sleepSession = session
                    session.habitMetrics = dailyHabitMetrics
                    
                    // Save the context
                    try self.context.save()
                    
                    print("[SleepAnalysisEngine] Successfully linked and saved habit metrics to session for \(session.ownershipDay)")
                    completion(true)
                    
                } catch {
                    print("[SleepAnalysisEngine] Failed to save habit metrics to CoreData: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    /// Finds or creates a DailyHabitMetrics entity for the given date
    private func findOrCreateDailyHabitMetrics(for date: Date) -> DailyHabitMetrics {
        let request: NSFetchRequest<DailyHabitMetrics> = DailyHabitMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", date as NSDate)
        request.fetchLimit = 1
        
        do {
            if let existingMetrics = try context.fetch(request).first {
                print("[SleepAnalysisEngine] Found existing DailyHabitMetrics for \(date)")
                return existingMetrics
            }
        } catch {
            print("[SleepAnalysisEngine] Failed to fetch existing DailyHabitMetrics: \(error)")
        }
        
        // Create new DailyHabitMetrics
        print("[SleepAnalysisEngine] Creating new DailyHabitMetrics for \(date)")
        let newMetrics = DailyHabitMetrics(context: context)
        newMetrics.date = date
        newMetrics.steps = 0.0
        newMetrics.exerciseTime = 0.0
        newMetrics.timeinDaylight = 0.0
        
        return newMetrics
    }
    
    /// Asynchronously fetches HealthKit workout data for the 24 hours preceding the session's ownershipDay and links it to the session
    private func fetchAndLinkWorkouts(for session: SleepSessionV2, completion: @escaping (Bool) -> Void) {
        // Calculate the 24-hour window preceding ownershipDay
        let endDate = session.ownershipDay
        guard let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: endDate) else {
            print("Failed to calculate start date for workout fetching")
            completion(false)
            return
        }
        
        print("[SleepAnalysisEngine] Fetching workouts from \(startDate) to \(endDate) for session \(session.ownershipDay)")
        
        // Use HealthKitManager to fetch workouts
        HealthKitManager.shared.fetchWorkouts(startDate: startDate, endDate: endDate) { [weak self] workoutDataArray, error in
            guard let self = self else {
                print("[SleepAnalysisEngine] Self was deallocated during workout fetch")
                completion(false)
                return
            }
            
            if let error = error {
                print("[SleepAnalysisEngine] Failed to fetch workouts: \(error)")
                completion(false)
                return
            }
            
            guard let workoutDataArray = workoutDataArray else {
                print("[SleepAnalysisEngine] No workout data returned (nil)")
                completion(false)
                return
            }
            
            print("[SleepAnalysisEngine] Successfully fetched \(workoutDataArray.count) workouts")
            
            // Create Workout entities and link to session on the CoreData queue
            self.context.perform {
                do {
                    for workoutData in workoutDataArray {
                        // Check if workout already exists to avoid duplicates
                        let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "uuid == %@", workoutData.uuid as CVarArg)
                        fetchRequest.fetchLimit = 1
                        
                        let existingWorkouts = try self.context.fetch(fetchRequest)
                        if existingWorkouts.isEmpty {
                            // Create new workout entity
                            let workout = Workout(context: self.context)
                            workout.uuid = workoutData.uuid
                            workout.date = workoutData.date
                            workout.workoutType = workoutData.workoutType
                            workout.workoutLength = workoutData.workoutLength
                            workout.timeOfDay = workoutData.timeOfDay
                            workout.calories = workoutData.calories ?? 0.0
                            workout.distance = workoutData.distance ?? 0.0
                            workout.averageHeartRate = workoutData.averageHeartRate ?? 0.0
                            
                            // Link workout to session
                            workout.sleepSession = session
                            session.addToWorkouts(workout)
                        } else {
                            print("[SleepAnalysisEngine] Workout \(workoutData.uuid) already exists, skipping")
                        }
                    }
                    
                    // Save the context
                    try self.context.save()
                    
                    print("[SleepAnalysisEngine] Successfully linked and saved \(workoutDataArray.count) workouts to session for \(session.ownershipDay)")
                    completion(true)
                    
                } catch {
                    print("[SleepAnalysisEngine] Failed to save workouts to CoreData: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    /// Phase 2: Finalization step to link temperature, run recovery analysis, and mark the session as complete.
    /// This is designed to be called after the initial analysis.
    func runFinalization() {
        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.predicate = NSPredicate(format: "isFinalized == NO")
        
        do {
            let unfinalizedSessions = try context.fetch(request)
            if unfinalizedSessions.isEmpty {
                return
            }
            
            print("[SleepAnalysisEngine] Found \(unfinalizedSessions.count) unfinalized sessions to finalize.")
            let recoveryCalculator = RecoveryScoreCalculator(context: context)
            
            for session in unfinalizedSessions {
                // 1. Link any available wrist temperature data.
                linkWristTemperatureSamples(to: session, for: session.ownershipDay)

                // 2. Fetch all other health metrics.
                HealthMetricsManager.shared.fetchAllHealthMetrics(for: session) { success in
                    if success {
                        // 3. Run recovery analysis now that all data is present.
                        recoveryCalculator.calculateAndStoreRecoveryMetrics(for: session)
                        
                        // 4. Mark the session as finalized.
                        session.isFinalized = true
                        print("[SleepAnalysisEngine] Successfully finalized session for \(session.ownershipDay).")
                    } else {
                        print("[SleepAnalysisEngine] Skipping finalization for session \(session.ownershipDay) due to metric fetch failure.")
                    }
                }
            }
            
            if context.hasChanges {
                try context.save()
                print("[SleepAnalysisEngine] Successfully finalized \(unfinalizedSessions.count) sessions.")
            }
            
        } catch {
            print("Failed to fetch or finalize sleep sessions: \(error)")
        }
    }
    
    /// Phase 2: Post-processing step to calculate recovery metrics for all sessions
    /// that have the necessary health data but haven't had their recovery calculated yet.
    /// This is designed to be called after all HealthKit syncing and initial data processing is complete.
    func runRecoveryAnalysisForAllEligibleSessions() async {
        let recoveryCalculator = RecoveryScoreCalculator(context: context)
        
        await context.perform {
            // Fetch all sessions that need recovery calculation
            let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            // A session is eligible if its recovery z-score is still the sentinel value (-100.0)
            request.predicate = NSPredicate(format: "hrvStatus == -100.0")
            request.sortDescriptors = [NSSortDescriptor(key: "ownershipDay", ascending: true)]
            
            do {
                let eligibleSessions = try self.context.fetch(request)
                if eligibleSessions.isEmpty {
                    print("[SleepAnalysisEngine] No new sessions eligible for recovery analysis.")
                    return
                }
                
                print("[SleepAnalysisEngine] Found \(eligibleSessions.count) sessions for recovery analysis.")
                
                for session in eligibleSessions {
                    // print("Calculating recovery for session: \(session.ownershipDay)")
                    recoveryCalculator.calculateAndStoreRecoveryMetrics(for: session)
                }
                
                // Save the context after all calculations are done.
                if self.context.hasChanges {
                    try self.context.save()
                    print("[SleepAnalysisEngine] Successfully saved context after recovery analysis.")
                }
                
            } catch {
                print("Failed to fetch or process eligible sessions for recovery analysis: \(error)")
            }
        }
    }
}
