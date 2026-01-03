import Foundation
import CoreData
import HealthKit

/// Coordinates the fetching and linking of all health data types to sleep sessions
/// Solves race condition issues by batching all data fetching and linking operations
class SleepSessionDataCoordinator {
    static let shared = SleepSessionDataCoordinator()
    
    private let healthKitManager = HealthKitManager.shared
    
    private init() {}
    
    /// Coordinates fetching and linking of all health data types to a sleep session
    /// This replaces individual calls to fetchAndLinkWorkouts, etc. to prevent race conditions
    @MainActor
    func linkAllHealthDataToSession(_ session: SleepSessionV2, context: NSManagedObjectContext) async {
        print("[SleepSessionDataCoordinator] Starting coordinated health data linking for session: \(session.ownershipDay)")
        
        // Calculate the 24-hour window preceding ownershipDay for daily metrics (habits & workouts)
        let ownershipDay = session.ownershipDay
        guard let dailyStartDate = Calendar.current.date(byAdding: .hour, value: -24, to: ownershipDay) else {
            print("[SleepSessionDataCoordinator] Failed to calculate daily start date")
            return
        }
        let dailyEndDate = ownershipDay
        
        print("[SleepSessionDataCoordinator] Fetching daily metrics from \(dailyStartDate) to \(dailyEndDate)")
        
        // Fetch both data types concurrently using correct 24-hour daily window
        async let habitDataTask = fetchHabitMetrics(startDate: dailyStartDate, endDate: dailyEndDate)
        async let workoutDataTask = fetchWorkoutData(startDate: dailyStartDate, endDate: dailyEndDate)
        
        // Wait for all data to be fetched
        let (habitResult, workoutResult) = await (habitDataTask, workoutDataTask)
        
        // Perform atomic linking in a single Core Data operation
        context.performAndWait {
            var hasChanges = false
            
            // Link habit metrics
            if case .success(let habitData) = habitResult {
                hasChanges = self.linkHabitMetrics(habitData, to: session, context: context) || hasChanges
            } else if case .failure(let error) = habitResult {
                print("[SleepSessionDataCoordinator] Habit metrics fetch failed: \(error)")
            }
            
            // Link workout data
            if case .success(let workoutData) = workoutResult {
                hasChanges = self.linkWorkoutData(workoutData, to: session, context: context) || hasChanges
            } else if case .failure(let error) = workoutResult {
                print("[SleepSessionDataCoordinator] Workout data fetch failed: \(error)")
            }
            
            // Link unlinked manual habits
            hasChanges = self.linkUnlinkedManualHabits(to: session, context: context) || hasChanges
            
            // Calculate recovery metrics after all other data is linked
            if hasChanges {
                hasChanges = self.calculateRecoveryMetrics(for: session, context: context) || hasChanges
            }
            
            // Save all changes atomically
            if hasChanges {
                do {
                    try context.save()
                    print("[SleepSessionDataCoordinator] Successfully linked all health data to session")
                } catch {
                    print("[SleepSessionDataCoordinator] Error saving linked health data: \(error)")
                }
            } else {
                print("[SleepSessionDataCoordinator] No health data changes to save")
            }
        }
    }
    
    // MARK: - Private Data Fetching Methods
    
    private func fetchHabitMetrics(startDate: Date, endDate: Date) async -> Result<HabitMetrics?, Error> {
        return await withCheckedContinuation { continuation in
            healthKitManager.fetchHabitMetrics(startDate: startDate, endDate: endDate) { metrics, error in
                if let error = error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(metrics))
                }
            }
        }
    }
    
    private func fetchWorkoutData(startDate: Date, endDate: Date) async -> Result<[WorkoutData], Error> {
        return await withCheckedContinuation { continuation in
            healthKitManager.fetchWorkouts(startDate: startDate, endDate: endDate) { workouts, error in
                if let error = error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(workouts ?? []))
                }
            }
        }
    }
    
    // MARK: - Private Linking Methods
    
    private func calculateRecoveryMetrics(for session: SleepSessionV2, context: NSManagedObjectContext) -> Bool {
        let recoveryCalculator = RecoveryScoreCalculator(context: context)
        recoveryCalculator.calculateAndStoreRecoveryMetrics(for: session)
        print("[SleepSessionDataCoordinator] Calculated recovery metrics for session")
        return true
    }
    
    private func linkHabitMetrics(_ metrics: HabitMetrics?, to session: SleepSessionV2, context: NSManagedObjectContext) -> Bool {
        guard let metrics = metrics else {
            print("[SleepSessionDataCoordinator] No habit metrics to link")
            return false
        }
        
        // Create or update DailyHabitMetrics
        let habitMetrics: DailyHabitMetrics
        if let existing = session.habitMetrics {
            habitMetrics = existing
        } else {
            habitMetrics = DailyHabitMetrics(context: context)
            session.habitMetrics = habitMetrics
        }
        
        // Update habit metrics
        habitMetrics.steps = metrics.steps
        habitMetrics.exerciseTime = metrics.exerciseTime
        habitMetrics.timeinDaylight = metrics.timeInDaylight
        habitMetrics.date = session.ownershipDay
        habitMetrics.sleepSession = session
        
        print("[SleepSessionDataCoordinator] Linked habit metrics: Steps=\(metrics.steps), Exercise=\(metrics.exerciseTime)min, Daylight=\(metrics.timeInDaylight)min")
        return true
    }
    
    private func linkWorkoutData(_ workoutDataArray: [WorkoutData], to session: SleepSessionV2, context: NSManagedObjectContext) -> Bool {
        guard !workoutDataArray.isEmpty else {
            print("[SleepSessionDataCoordinator] No workout data to link")
            return false
        }
        
        // Remove existing workouts to avoid duplicates
        if let existingWorkouts = session.workouts as? Set<Workout> {
            for workout in existingWorkouts {
                context.delete(workout)
            }
        }
        
        // Create new workout entities
        var newWorkouts = Set<Workout>()
        for workoutData in workoutDataArray {
            let workout = Workout(context: context)
            workout.uuid = UUID()
            workout.date = workoutData.date
            workout.workoutType = workoutData.workoutType
            workout.workoutLength = workoutData.workoutLength
            workout.timeOfDay = workoutData.timeOfDay
            workout.calories = workoutData.calories ?? 0
            workout.distance = workoutData.distance ?? 0
            workout.averageHeartRate = workoutData.averageHeartRate ?? 0
            workout.sleepSession = session
            newWorkouts.insert(workout)
        }
        
        session.workouts = NSSet(set: newWorkouts)
        
        print("[SleepSessionDataCoordinator] Linked \(workoutDataArray.count) workouts to session")
        return true
    }
    
    private func linkUnlinkedManualHabits(to session: SleepSessionV2, context: NSManagedObjectContext) -> Bool {
        let ownershipDay = session.ownershipDay
        guard let lookbackStart = Calendar.current.date(byAdding: .hour, value: -24, to: ownershipDay) else {
            print("[SleepSessionDataCoordinator] Failed to calculate 24-hour lookback window")
            return false
        }
        
        // Find unlinked manual habits in the 24-hour window preceding ownershipDay
        let fetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: 
            "isResolved == NO AND entryDate >= %@ AND entryDate <= %@", 
            lookbackStart as NSDate, ownershipDay as NSDate)
        
        do {
            let unlinkedHabits = try context.fetch(fetchRequest)
            
            guard !unlinkedHabits.isEmpty else {
                print("[SleepSessionDataCoordinator] No unlinked manual habits to link")
                return false
            }
            
            // Link all unlinked habits to this session
            for habit in unlinkedHabits {
                habit.sleepSession = session
                habit.isResolved = true
            }
            
            print("[SleepSessionDataCoordinator] Linked \(unlinkedHabits.count) manual habits to session: \(session.ownershipDay)")
            return true
            
        } catch {
            print("[SleepSessionDataCoordinator] Error fetching unlinked manual habits: \(error)")
            return false
        }
    }
}
