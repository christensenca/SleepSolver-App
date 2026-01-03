import Foundation
import HealthKit
import CoreData

// MARK: - Habit Metrics Data Structure

struct HabitMetrics {
    let steps: Double
    let exerciseTime: Double
    let timeInDaylight: Double
}

// MARK: - Workout Data Structure

struct WorkoutData {
    let uuid: UUID
    let date: Date
    let workoutType: String
    let workoutLength: Double // Duration in seconds
    let timeOfDay: String
    let calories: Double?
    let distance: Double?
    let averageHeartRate: Double?
}

// MARK: - Health Kit Manager

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    // Define the sleep analysis type identifier
    private let sleepAnalysisTypeIdentifier = HKCategoryTypeIdentifier.sleepAnalysis
        private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let wristTemperatureType = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
    private let spO2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let respiratoryRateType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!

    // MARK: - New Habit Metric Types
    private let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let appleExerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let timeInDaylightType = HKQuantityType.quantityType(forIdentifier: .timeInDaylight)!
    
    // MARK: - Workout Types
    private let workoutType = HKWorkoutType.workoutType()

    private init() {} // Private initializer for singleton

    // MARK: - Query Execution
    
    /// Execute a HealthKit query - wrapper for external access to healthStore
    func executeQuery(_ query: HKQuery) {
        healthStore.execute(query)
    }

    // MARK: - Authorization

    func checkAuthorizationStatus(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: sleepAnalysisTypeIdentifier) else {
            completion(false)
            return
        }

        let status = healthStore.authorizationStatus(for: sleepType)
        completion(status == .sharingAuthorized)
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, HealthKitError.notAvailableOnDevice)
            return
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: sleepAnalysisTypeIdentifier) else {
            completion(false, HealthKitError.dataTypeNotAvailable("Sleep Analysis"))
            return
        }

        // Define all types to read
        let typesToRead: Set<HKObjectType> = [
            sleepType,
            heartRateType,
            hrvType,
            wristTemperatureType,
            spO2Type,
            respiratoryRateType,
            stepCountType,
            appleExerciseTimeType,
            timeInDaylightType,
            workoutType
        ]
        
        // Define types to write (if any, currently empty)
        let typesToWrite: Set<HKSampleType> = []

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            // Call the completion handler with the result
            completion(success, error)
        }
    }

    // MARK: - Sleep Data Synchronization
    // Note: Sleep data sync has been moved to NewSleepDataManager and SleepAnalysisEngine
    
    // MARK: - Historical Sleep Data Fetching (Deprecated - use NewSleepDataManager)
    // Historical sleep data fetching has been moved to NewSleepDataManager
    // MARK: - Sleep Session Processing (Deprecated - use NewSleepDataManager)
    // Sleep session processing has been moved to NewSleepDataManager and SleepAnalysisEngine
    
    // MARK: - Public Historical Data Sync Methods
    
    public func syncHealthMetricsForDateRange(_ startDate: Date, _ endDate: Date, context: NSManagedObjectContext) async {
        let calendar = Calendar.current
        let dayCount = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        
        print("[HKM] syncHealthMetricsForDateRange: Syncing \(dayCount) days from \(startDate) to \(endDate)")
        
        // Always use day-by-day method for historical onboarding to ensure complete data
        // Only use bulk optimization for chart data requests (not during onboarding)
        await syncHealthMetricsByDay(startDate, endDate, context: context)
    }
    
    /// Day-by-day sync for small date ranges (more accurate, slower)
    private func syncHealthMetricsByDay(_ startDate: Date, _ endDate: Date, context: NSManagedObjectContext) async {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let endOfRange = calendar.startOfDay(for: endDate)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        
        print("[HKM] syncHealthMetricsByDay: Processing from \(formatter.string(from: currentDate)) to \(formatter.string(from: endOfRange))")
        
        while currentDate <= endOfRange {
            print("[HKM] Processing date: \(formatter.string(from: currentDate)) (raw: \(currentDate))")
            // Note: Habit data syncing is now handled by SleepDataSyncCoordinator
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) {
                currentDate = nextDay
            } else {
                break
            }
        }
        
        print("[HKM] syncHealthMetricsByDay: Completed processing range")
    }

    // MARK: - Quantitative Habit Data Synchronization
    // Note: Habit data syncing has been moved to SleepDataSyncCoordinator for centralized management
    
    // MARK: - Habit Metric Fetching for Time Range

    /// Fetches habit metrics (steps, exercise time, daylight time) for a specific time range
    func fetchHabitMetrics(startDate: Date, endDate: Date, completion: @escaping (HabitMetrics?, Error?) -> Void) {
        // Use a private queue for thread-safe access to shared state
        let syncQueue = DispatchQueue(label: "habitMetricsFetch", qos: .userInitiated)
        let group = DispatchGroup()
        
        // Thread-safe storage for results
        var results: [String: Double] = [:]
        var errors: [String: Error] = [:]
        
        // Fetch steps
        group.enter()
        fetchSumQuantityStatisticsForRange(
            for: stepCountType,
            unit: .count(),
            startDate: startDate,
            endDate: endDate
        ) { value, error in
            syncQueue.sync {
                if let error = error {
                    errors["steps"] = error
                    results["steps"] = 0.0 // Default to 0 on error
                } else {
                    results["steps"] = value ?? 0.0
                }
            }
            group.leave()
        }
        
        // Fetch exercise time
        group.enter()
        fetchSumQuantityStatisticsForRange(
            for: appleExerciseTimeType,
            unit: .minute(),
            startDate: startDate,
            endDate: endDate
        ) { value, error in
            syncQueue.sync {
                if let error = error {
                    errors["exerciseTime"] = error
                    results["exerciseTime"] = 0.0 // Default to 0 on error
                } else {
                    results["exerciseTime"] = value ?? 0.0
                }
            }
            group.leave()
        }
        
        // Fetch daylight time
        group.enter()
        fetchSumQuantityStatisticsForRange(
            for: timeInDaylightType,
            unit: .minute(),
            startDate: startDate,
            endDate: endDate
        ) { value, error in
            syncQueue.sync {
                if let error = error {
                    errors["timeInDaylight"] = error
                    results["timeInDaylight"] = 0.0 // Default to 0 on error
                } else {
                    results["timeInDaylight"] = value ?? 0.0
                }
            }
            group.leave()
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            // Create habit metrics with available data (graceful degradation)
            let habitMetrics = HabitMetrics(
                steps: results["steps"] ?? 0.0,
                exerciseTime: results["exerciseTime"] ?? 0.0,
                timeInDaylight: results["timeInDaylight"] ?? 0.0
            )
            
            // Check if errors are due to "no data available" vs actual failures
            let noDataErrors = errors.values.filter { error in
                let errorString = error.localizedDescription.lowercased()
                return errorString.contains("no data available") || 
                       errorString.contains("no samples") ||
                       errorString.contains("predicate") ||
                       errorString.contains("no data") ||
                       errorString.contains("not available") ||
                       (error as NSError).code == 5 // HKErrorNoData
            }
            
            // Only fail if ALL metrics failed due to actual errors (not "no data" errors)
            if errors.count == 3 && noDataErrors.count < 3 {
                // All metrics failed with real errors - return the first non-"no data" error
                let firstRealError = errors.values.first { error in
                    let errorString = error.localizedDescription.lowercased()
                    return !errorString.contains("no data available") && 
                           !errorString.contains("no samples") &&
                           !errorString.contains("predicate")
                } ?? errors.values.first ?? NSError(domain: "HealthKitManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "All habit metrics failed to fetch"])
                completion(nil, firstRealError)
            } else {
                // At least some metrics succeeded OR all failures are "no data" errors - return data (possibly zeros)
                if !errors.isEmpty && noDataErrors.count < errors.count {
                    print("[HealthKitManager] Partial habit metrics fetch - errors: \(errors.keys)")
                } else if noDataErrors.count == errors.count && !errors.isEmpty {
                    print("[HealthKitManager] No habit data available for time period (returning zeros)")
                }
                completion(habitMetrics, nil)
            }
        }
    }
    
    /// Generic function to fetch sum statistics for a quantity type within a date range
    private func fetchSumQuantityStatisticsForRange(
        for quantityType: HKQuantityType,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        completion: @escaping (Double?, Error?) -> Void
    ) {
        // Create a predicate to filter samples within the desired date range
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        // Use HKStatisticsQuery to get the sum, which handles multiple sources correctly.
        let query = HKStatisticsQuery(quantityType: quantityType,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, statistics, error in
            guard error == nil else {
                // Enhanced error logging to identify why specific metrics fail
                let typeName = quantityType.identifier
                print("[HealthKitManager] ❌ Query failed for \(typeName): \(error!.localizedDescription)")
                if let hkError = error as? HKError {
                    print("[HealthKitManager] HKError code: \(hkError.code.rawValue), userInfo: \(hkError.userInfo)")
                }
                completion(nil, error)
                return
            }

            if let sumQuantity = statistics?.sumQuantity() {
                let sum = sumQuantity.doubleValue(for: unit)
                let typeName = quantityType.identifier
                print("[HealthKitManager] ✅ \(typeName): \(sum) \(unit.unitString)")
                completion(sum, nil)
            } else {
                // No data found for this period, or sum is not applicable.
                // For cumulative sums like steps, this typically means 0.
                let typeName = quantityType.identifier
                print("[HealthKitManager] ⚪ \(typeName): No data (returning 0.0)")
                completion(0.0, nil)
            }
        }

        // Execute the query
        healthStore.execute(query)
    }

    // MARK: - Sleep-specific Metric Fetching (SpO2 & Respiratory Rate)
    
    public func fetchAverageSpO2(startDate: Date, endDate: Date, completion: @escaping (Double?, Error?) -> Void) {
        fetchAverageQuantityStatistics(
            for: spO2Type,
            unit: HKUnit.percent(),
            startDate: startDate,
            endDate: endDate
        ) { value, error in
            // SpO2 in HealthKit is stored as a fraction (0.0-1.0), convert to percentage (0-100)
            if let spO2Value = value {
                completion(spO2Value * 100.0, error)
            } else {
                completion(value, error)
            }
        }
    }
    
    public func fetchAverageRespiratoryRate(startDate: Date, endDate: Date, completion: @escaping (Double?, Error?) -> Void) {
        fetchAverageQuantityStatistics(
            for: respiratoryRateType,
            unit: .count().unitDivided(by: .minute()),
            startDate: startDate,
            endDate: endDate,
            completion: completion
        )
    }
    
    // Generic function to fetch average statistics for a quantity type over a date range
    public func fetchAverageQuantityStatistics(
        for quantityType: HKQuantityType,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        completion: @escaping (Double?, Error?) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, statistics, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let averageQuantity = statistics?.averageQuantity() {
                    let value = averageQuantity.doubleValue(for: unit)
                    completion(value, nil)
                } else {
                    completion(0.0, nil)
                }
            }
        }

        // Execute the query
        healthStore.execute(query)
    }

    // MARK: - Data Processing (Sleep related)
    // private func processAndUpsertSleepSession(...)

    // MARK: - Core Data Saving (Upserting)
    // Note: Sleep session upserting has been moved to NewSleepDataManager and SleepAnalysisEngine
    // The old upsertSleepSessionInCoreData method has been removed as it was disabled and replaced by the new pipeline

    private func upsertDailyHabitMetricsInCoreData( // Renamed from saveDailyHabitMetrics
        date: Date,
        steps: Double?,
        exerciseTime: Double?,
        timeInDaylight: Double?,
        context: NSManagedObjectContext // Context is already a parameter
        // completion: @escaping (Error?) -> Void // Removed completion for this direct version
    ) {
        context.perform {
            let fetchRequest: NSFetchRequest<DailyHabitMetrics> = DailyHabitMetrics.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "date == %@", date as CVarArg)
            fetchRequest.fetchLimit = 1

            var metrics: DailyHabitMetrics
            do {
                let existingMetrics = try context.fetch(fetchRequest)
                if let existingMetric = existingMetrics.first {
                    metrics = existingMetric
                } else {
                    metrics = DailyHabitMetrics(context: context)
                    metrics.date = date
                }

                // Update metric values
                if let steps = steps { metrics.steps = steps }
                if let exerciseTime = exerciseTime { metrics.exerciseTime = exerciseTime }
                if let timeInDaylight = timeInDaylight { metrics.timeinDaylight = timeInDaylight }

                // Note: Habit metrics are now standalone and not linked to sleep sessions

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                print("[HKM] Failed to save or fetch DailyHabitMetrics: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check authorization status for habit metrics and workout data types
    func checkHabitMetricsAndWorkoutAuthorization() {
        let quantityDataTypes: [(String, HKQuantityType)] = [
            ("Steps", stepCountType),
            ("Exercise Time", appleExerciseTimeType),
            ("Time in Daylight", timeInDaylightType)
        ]
        
        print("[HealthKitManager] 🔐 Habit Metrics & Workout Authorization Status:")
        for (name, type) in quantityDataTypes {
            let status = healthStore.authorizationStatus(for: type)
            let statusName = authorizationStatusName(status)
            print("[HealthKitManager] - \(name): \(statusName)")
        }
        
        // Check workout authorization separately since it's a different type
        let workoutStatus = healthStore.authorizationStatus(for: workoutType)
        let workoutStatusName = authorizationStatusName(workoutStatus)
        print("[HealthKitManager] - Workouts: \(workoutStatusName)")
    }
    
    private func authorizationStatusName(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .sharingDenied: return "❌ DENIED"
        case .sharingAuthorized: return "✅ Authorized"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Workout Fetching for Time Range
    
    /// Fetches workout data for a specific time range
    func fetchWorkouts(startDate: Date, endDate: Date, completion: @escaping ([WorkoutData]?, Error?) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            guard error == nil else {
                print("[HealthKitManager] ❌ Workout query failed: \(error!.localizedDescription)")
                completion(nil, error)
                return
            }
            
            guard let workoutSamples = samples as? [HKWorkout] else {
                print("[HealthKitManager] ⚪ No workout data found for period")
                completion([], nil)
                return
            }
            
            var workoutDataArray: [WorkoutData] = []
            
            for workout in workoutSamples {
                let workoutData = WorkoutData(
                    uuid: workout.uuid,
                    date: workout.startDate,
                    workoutType: self.workoutTypeString(from: workout.workoutActivityType),
                    workoutLength: workout.duration,
                    timeOfDay: self.calculateTimeOfDay(from: workout.startDate),
                    calories: self.extractCalories(from: workout),
                    distance: workout.totalDistance?.doubleValue(for: .meter()),
                    averageHeartRate: self.extractAverageHeartRate(from: workout)
                )
                workoutDataArray.append(workoutData)
            }
            
            print("[HealthKitManager] ✅ Found \(workoutDataArray.count) workouts in period")
            completion(workoutDataArray, nil)
        }
        
        healthStore.execute(query)
    }
    
    /// Convert HKWorkoutActivityType to readable string
    private func workoutTypeString(from activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: return "Running"
        case .cycling: return "Cycling" 
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Weight Training"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .baseball: return "Baseball"
        case .americanFootball: return "Football"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairs: return "Stairs"
        case .golf: return "Golf"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .crossTraining: return "Cross Training"
        case .mixedCardio: return "Mixed Cardio"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flexibility"
        case .cooldown: return "Cooldown"
        case .other: return "Other"
        case .archery: return "Archery"
        case .badminton: return "Badminton"
        case .barre: return "Barre"
        case .bowling: return "Bowling"
        case .climbing: return "Climbing"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .curling: return "Curling"
        case .downhillSkiing: return "Downhill Skiing"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .fitnessGaming: return "Fitness Gaming"
        case .handball: return "Handball"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .mindAndBody: return "Mind and Body"
        case .play: return "Play"
        case .preparationAndRecovery: return "Preparation and Recovery"
        case .racquetball: return "Racquetball"
        case .rugby: return "Rugby"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating Sports"
        case .snowSports: return "Snow Sports"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .surfingSports: return "Surfing Sports"
        case .tableTennis: return "Table Tennis"
        case .taiChi: return "Tai Chi"
        case .trackAndField: return "Track and Field"
        case .volleyball: return "Volleyball"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .stepTraining: return "Step Training"
        case .wheelchairWalkPace: return "Wheelchair Walk Pace"
        case .wheelchairRunPace: return "Wheelchair Run Pace"
        case .paddleSports: return "Paddle Sports"
        case .kickboxing: return "Kickboxing"
        case .cardioDance: return "Cardio Dance"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .australianFootball: return "Australian Football"
        case .cricket: return "Cricket"
        case .equestrianSports: return "Equestrian Sports"
        case .gymnastics: return "Gymnastics"
        case .hockey: return "Hockey"
        case .snowboarding: return "Snowboarding"
        case .handCycling: return "Hand Cycling"
        case .discSports: return "Disc Sports"
        case .swimBikeRun: return "Swim Bike Run"
        case .transition: return "Transition"
        case .underwaterDiving: return "Underwater Diving"
        case .stairClimbing: return "Stair Climbing"
        case .danceInspiredTraining : return "Dance Inspired Training"
        case .mixedMetabolicCardioTraining: return "Mixed Metabolic Cardio Training"
        @unknown default: return "Unknown"
        }
    }
    
    /// Calculate time of day category from workout start time
    private func calculateTimeOfDay(from date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        switch hour {
        case 5..<12: return "Morning"
        case 12..<18: return "Afternoon"
        default: return "Evening"
        }
    }
    
    /// Extract average heart rate from workout statistics
    private func extractAverageHeartRate(from workout: HKWorkout) -> Double? {
        guard let heartRateStats = workout.statistics(for: heartRateType),
              let averageQuantity = heartRateStats.averageQuantity() else {
            return nil
        }
        
        return averageQuantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }
    
    /// Extract calories from workout statistics (modern approach for iOS 18+)
    private func extractCalories(from workout: HKWorkout) -> Double? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let energyStats = workout.statistics(for: energyType),
              let totalEnergy = energyStats.sumQuantity() else {
            return nil
        }
        
        return totalEnergy.doubleValue(for: .kilocalorie())
    }

}

// MARK: - Error Handling

extension HealthKitManager {
    enum HealthKitError: LocalizedError {
        case notAvailableOnDevice
        case dataTypeNotAvailable(String)
        case dateIntervalError
        case invalidSampleType
        case aggregationError(String)
        case coreDataSaveError(Error)

        var errorDescription: String? {
            switch self {
            case .notAvailableOnDevice:
                return "HealthKit is not available on this device."
            case .dataTypeNotAvailable(let type):
                return "HealthKit data type '\(type)' is not available."
            case .dateIntervalError:
                return "Could not create the required date interval for the HealthKit query."
            case .invalidSampleType:
                return "Received an unexpected sample type from HealthKit."
            case .aggregationError(let message):
                return "Failed to aggregate sleep samples: \(message)"
            case .coreDataSaveError(let underlyingError):
                return "Failed to save sleep data to Core Data: \(underlyingError.localizedDescription)"
            }
        }
    }
}
