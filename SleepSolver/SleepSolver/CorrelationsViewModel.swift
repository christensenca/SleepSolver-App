import Foundation
import CoreData
import Combine
import SwiftUI

// Enum for available correlation metrics
enum CorrelationMetric: CaseIterable, Identifiable {
    case sleepScore
    case sleepDuration
    case totalAwakeTime
    case hrv
    case heartRate
    case deepSleep
    case remSleep
    
    var id: Self { self }
    
    var displayName: String {
        switch self {
        case .sleepScore: return "Sleep Score"
        case .sleepDuration: return "Sleep Duration"
        case .totalAwakeTime: return "Total Awake Time"
        case .hrv: return "HRV"
        case .heartRate: return "Heart Rate"
        case .deepSleep: return "Deep Sleep"
        case .remSleep: return "REM Sleep"
        }
    }
    
    var icon: String {
        switch self {
        case .sleepScore: return "moon.stars"
        case .sleepDuration: return "clock"
        case .totalAwakeTime: return "eye.slash"
        case .hrv: return "waveform.path.ecg.rectangle"
        case .heartRate: return "heart"
        case .deepSleep: return "moon.zzz"
        case .remSleep: return "eye"
        }
    }
}

// Enum for time window options
enum TimeWindow: CaseIterable, Identifiable {
    case days15
    case days30
    case days45
    case days60
    case days90
    
    var id: Self { self }
    
    var displayName: String {
        switch self {
        case .days15: return "15 days"
        case .days30: return "30 days"
        case .days45: return "45 days"
        case .days60: return "60 days"
        case .days90: return "90 days"
        }
    }
    
    var dayCount: Int {
        switch self {
        case .days15: return 15
        case .days30: return 30
        case .days45: return 45
        case .days60: return 60
        case .days90: return 90
        }
    }
}

// New struct for correlation summaries (pairwise results)
struct CorrelationSummary: Identifiable, Hashable {
    let id = UUID()
    let healthMetricName: String
    let healthMetricIcon: String
    let sleepMetricName: String
    let sleepMetricIcon: String
    let correlationCoefficient: Double // Pearson correlation coefficient (-1 to +1)
    let percentageChange: Double // e.g., +15.5% (from best bin analysis)
    let isSignificant: Bool
    let binAnalysisResult: BinAnalysisResult? // For drill-down
    let habitImpact: Double? // For habits
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CorrelationSummary, rhs: CorrelationSummary) -> Bool {
        lhs.id == rhs.id
    }
}

// Structure to hold binning analysis results
struct BinAnalysisResult: Identifiable {
    let id = UUID()
    let healthMetricName: String
    let healthMetricIcon: String
    let sleepMetricName: String
    let bins: [HealthMetricBin]
    let totalSamples: Int
    let status: BinAnalysisStatus
    let baseline: Double // Average sleep metric value for the entire time window
    
    var isValid: Bool {
        switch status {
        case .valid:
            return true
        case .insufficientData:
            return false
        }
    }
}

// Structure for individual bins in the analysis
struct HealthMetricBin: Identifiable {
    let id = UUID()
    let range: String // e.g., "0-30 min", "5000-8000 steps"
    let lowerBound: Double // Inclusive lower bound
    let upperBound: Double // Inclusive upper bound
    let averageSleepMetric: Double // Average sleep metric value for this bin
    let sampleCount: Int // Number of samples in this bin
}

enum BinAnalysisStatus: Equatable {
    case valid // Enough data points for meaningful binning
    case insufficientData(current: Int, required: Int) // Not enough data points
}

// New struct for grouped insights by sleep metric
struct SleepMetricGroup: Identifiable {
    let id = UUID()
    let sleepMetric: CorrelationMetric
    let topInsights: [RegressionInsight] // Top 3 by impact significance
    let additionalInsights: [RegressionInsight] // Rest of the insights
    var isExpanded: Bool = false

    var allInsights: [RegressionInsight] {
        topInsights + additionalInsights
    }
}

// Legacy structures for backward compatibility (can be removed later)
struct CorrelationResult: Identifiable {
    let id = UUID()
    let habitName: String
    let habitIcon: String // Icon from HabitDefinition
    let metricName: String // e.g., "Total Sleep Time", "Sleep Efficiency"
    let correlationValue: Double // Pearson correlation coefficient, for example
    let pValue: Double // Significance level
    let sampleSize: Int // Number of data points used
    let status: CorrelationStatus // Status of the correlation calculation
    
    var isValid: Bool {
        switch status {
        case .valid:
            return true
        case .insufficientData:
            return false
        }
    }
}

enum CorrelationStatus: Equatable {
    case valid // Enough data points for correlation
    case insufficientData(current: Int, required: Int) // Not enough data points
}

@MainActor
class CorrelationsViewModel: ObservableObject {
    @Published var binAnalysisResults: [BinAnalysisResult] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // Store raw unfiltered results
    private var rawAnalysisResults: [BinAnalysisResult] = []
    
    // Dropdown selections
    // @Published var selectedMetric: CorrelationMetric = .sleepScore
    // @Published var selectedTimeWindow: TimeWindow = .days90
    
    // New property for regression insights
    @Published var regressionInsights: [RegressionInsight] = []
    
    // New property for grouped insights by sleep metric
    @Published var sleepMetricGroups: [SleepMetricGroup] = []
    
    // Cache for insights to avoid recomputation
    private var cachedInsights: [RegressionInsight] = []
    private var insightsLastUpdated: Date?
    
    // Baseline progress for insufficient data
    @Published var baselineProgress: (current: Int, required: Int)? = nil
    
    // Filtering controls
    @Published var visibleHealthMetrics: Set<String> = ["Exercise Time", "Steps", "Time in Daylight"] {
        didSet {
            saveHealthMetricsFilter()
        }
    }
    @Published var visibleHabitNames: Set<String> = [] {
        didSet {
            saveHabitsFilter()
        }
    }
    @Published var availableHabitNames: [String] = []
    
    // Workout filtering controls
    @Published var visibleWorkoutTypes: Set<String> = [] {
        didSet {
            saveWorkoutTypesFilter()
        }
    }
    @Published var availableWorkoutTypes: [String] = []
    
    // Track whether habits have been initialized to prevent auto-reselection
    private var habitsHaveBeenInitialized: Bool = false {
        didSet {
            UserDefaults.standard.set(habitsHaveBeenInitialized, forKey: "correlations_habits_initialized")
        }
    }
    

    
    // Computed properties for different empty states
    var hasDataButAllFiltersHidden: Bool {
        let hasHealthMetrics = !rawAnalysisResults.filter { ["Exercise Time", "Steps", "Time in Daylight"].contains($0.healthMetricName) }.isEmpty
        let hasHabits = !availableHabitNames.isEmpty
        let hasWorkouts = !availableWorkoutTypes.isEmpty
        let allHealthMetricsHidden = visibleHealthMetrics.isEmpty
        let allHabitsHidden = visibleHabitNames.isEmpty && hasHabits
        let allWorkoutsHidden = visibleWorkoutTypes.isEmpty && hasWorkouts
        
        return (hasHealthMetrics || hasHabits || hasWorkouts) && allHealthMetricsHidden && allHabitsHidden && allWorkoutsHidden
    }
    
    var hasNeverRunAnalysis: Bool {
        return rawAnalysisResults.isEmpty
    }
    
    // Computed property to check if we have data but all habits are filtered out
    var hasDataButAllHabitsFiltered: Bool {
        return !availableHabitNames.isEmpty && visibleHabitNames.isEmpty
    }

    private let viewContext: NSManagedObjectContext
    private let calendar = Calendar.current
    
    // MARK: - Optimized 7-day Cache Properties (increased for better testing)
    private var cachedSleepSessions: [SleepSessionV2] = []
    private var cacheLastUpdated: Date? // Single source of truth - eliminates redundant date properties
    
    // Cache is valid if updated today
    private var isCacheValid: Bool {
        guard let lastUpdated = cacheLastUpdated else { return false }
        let today = calendar.startOfDay(for: Date())
        let lastUpdatedDay = calendar.startOfDay(for: lastUpdated)
        return lastUpdatedDay == today
    }

    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        // Load persisted filter settings
        loadPersistedFilterSettings()
    }
    
    // MARK: - Persistence Methods
    
    /// Load filter settings from UserDefaults
    private func loadPersistedFilterSettings() {
        // Load health metrics filter
        if let healthMetricsData = UserDefaults.standard.data(forKey: "correlations_visible_health_metrics"),
           let healthMetrics = try? JSONDecoder().decode(Set<String>.self, from: healthMetricsData) {
            visibleHealthMetrics = healthMetrics
        }
        
        // Load habits filter
        if let habitsData = UserDefaults.standard.data(forKey: "correlations_visible_habits"),
           let habits = try? JSONDecoder().decode(Set<String>.self, from: habitsData) {
            visibleHabitNames = habits
        }
        
        // Load workout types filter
        if let workoutTypesData = UserDefaults.standard.data(forKey: "correlations_visible_workout_types"),
           let workoutTypes = try? JSONDecoder().decode(Set<String>.self, from: workoutTypesData) {
            visibleWorkoutTypes = workoutTypes
        }
        
        // Load initialization state
        habitsHaveBeenInitialized = UserDefaults.standard.bool(forKey: "correlations_habits_initialized")
        
        print("[CorrelationsViewModel] Loaded persisted filters - Health metrics: \(visibleHealthMetrics), Habits: \(visibleHabitNames), Workout types: \(visibleWorkoutTypes), Initialized: \(habitsHaveBeenInitialized)")
    }
    
    /// Save health metrics filter to UserDefaults
    private func saveHealthMetricsFilter() {
        if let data = try? JSONEncoder().encode(visibleHealthMetrics) {
            UserDefaults.standard.set(data, forKey: "correlations_visible_health_metrics")
            print("[CorrelationsViewModel] Saved health metrics filter: \(visibleHealthMetrics)")
        }
    }
    
    /// Save habits filter to UserDefaults
    private func saveHabitsFilter() {
        if let data = try? JSONEncoder().encode(visibleHabitNames) {
            UserDefaults.standard.set(data, forKey: "correlations_visible_habits")
            print("[CorrelationsViewModel] Saved habits filter: \(visibleHabitNames)")
        }
    }
    
    /// Save workout types filter to UserDefaults
    private func saveWorkoutTypesFilter() {
        if let data = try? JSONEncoder().encode(visibleWorkoutTypes) {
            UserDefaults.standard.set(data, forKey: "correlations_visible_workout_types")
            print("[CorrelationsViewModel] Saved workout types filter: \(visibleWorkoutTypes)")
        }
    }
    
    // MARK: - Filtering Methods
    
    /// Toggle visibility of a health metric chart
    func toggleHealthMetric(_ metricName: String) {
        if visibleHealthMetrics.contains(metricName) {
            visibleHealthMetrics.remove(metricName)
        } else {
            visibleHealthMetrics.insert(metricName)
        }
        updateFilteredResults()
    }
    
    /// Toggle visibility of a habit within the combined habits chart
    func toggleHabit(_ habitName: String) {
        print("[CorrelationsViewModel] Toggling habit: \(habitName)")
        print("[CorrelationsViewModel] Before toggle - visibleHabitNames: \(visibleHabitNames)")
        
        if visibleHabitNames.contains(habitName) {
            visibleHabitNames.remove(habitName)
        } else {
            visibleHabitNames.insert(habitName)
        }
        
        print("[CorrelationsViewModel] After toggle - visibleHabitNames: \(visibleHabitNames)")
        print("[CorrelationsViewModel] Available habits: \(availableHabitNames)")
        
        updateFilteredResults()
    }
    
    /// Toggle visibility of a workout type chart
    func toggleWorkoutType(_ workoutType: String) {
        print("[CorrelationsViewModel] Toggling workout type: \(workoutType)")
        print("[CorrelationsViewModel] Before toggle - visibleWorkoutTypes: \(visibleWorkoutTypes)")
        
        if visibleWorkoutTypes.contains(workoutType) {
            visibleWorkoutTypes.remove(workoutType)
        } else {
            visibleWorkoutTypes.insert(workoutType)
        }
        
        print("[CorrelationsViewModel] After toggle - visibleWorkoutTypes: \(visibleWorkoutTypes)")
        print("[CorrelationsViewModel] Available workout types: \(availableWorkoutTypes)")
        
        updateFilteredResults()
    }
    
    /// Update the filtered results based on current selections
    private func updateFilteredResults() {
        print("[CorrelationsViewModel] updateFilteredResults called")
        print("[CorrelationsViewModel] Current visibleHabitNames: \(visibleHabitNames)")
        print("[CorrelationsViewModel] Current availableHabitNames: \(availableHabitNames)")
        
        // Apply filtering to the stored raw results instead of recalculating
        let filteredResults = applyFiltering(to: rawAnalysisResults)
        binAnalysisResults = filteredResults
        
        print("[CorrelationsViewModel] Applied filtering, now have \(filteredResults.count) results")
    }
    
    // MARK: - Cache Management
    
    /// Loads and caches 90 days of data
    private func loadAndCache90DaysData() async throws {
        let methodStartTime = CFAbsoluteTimeGetCurrent()
        print("[CorrelationsViewModel] Starting loadAndCache90DaysData() - measuring performance...")
        
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not calculate 90-day range"])
        }
        
        print("[CorrelationsViewModel] Date range: \(startDate) to \(endDate)")
        print("[CorrelationsViewModel] Cache validation - isCacheValid: \(isCacheValid)")
        print("[CorrelationsViewModel] Previous cache size: \(cachedSleepSessions.count) sessions")
        
        // STAGE 2: Setup CoreData fetch requests with timing
        let setupStartTime = CFAbsoluteTimeGetCurrent()
        
        // UPDATED: Fetch SleepSessionV2 for 90 days by ownershipDay
        let sleepRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        sleepRequest.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay <= %@ AND sleepScore > 0", startDate as NSDate, endDate as NSDate)
        sleepRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SleepSessionV2.ownershipDay, ascending: true)]
        sleepRequest.relationshipKeyPathsForPrefetching = ["habitMetrics", "manualHabits", "workouts"]
        sleepRequest.fetchBatchSize = 100
        sleepRequest.includesPropertyValues = true // Optimize for immediate property access
        sleepRequest.returnsObjectsAsFaults = false // Prefault objects for better performance
        
        let setupDuration = CFAbsoluteTimeGetCurrent() - setupStartTime
        print("[CorrelationsViewModel] TIMING: Fetch request setup took \(String(format: "%.3f", setupDuration))s")
        print("[CorrelationsViewModel] Fetch request configuration:")
        print("  - Predicate: ownershipDay >= \(startDate) AND ownershipDay <= \(endDate) AND sleepScore > 0")
        print("  - Batch size: 100")
        print("  - Prefetching: habitMetrics, manualHabits, workouts relationships")
        print("  - Returns faults: false")
        
        // STAGE 3: Execute sleep sessions fetch
        let fetchStartTime = CFAbsoluteTimeGetCurrent()
        print("[CorrelationsViewModel] Executing Core Data fetch request...")
        
        // STAGE 4: Await results
        cachedSleepSessions = try await viewContext.perform { [sleepRequest, viewContext] in
            try viewContext.fetch(sleepRequest)
        }
        
        let fetchDuration = CFAbsoluteTimeGetCurrent() - fetchStartTime
        print("[CorrelationsViewModel] TIMING: Sleep sessions fetch took \(String(format: "%.3f", fetchDuration))s")
        print("[CorrelationsViewModel] Fetch results: Found \(cachedSleepSessions.count) sleep sessions with sleepScore > 0")
        
        // Update cache metadata - single source of truth
        cacheLastUpdated = Date()
        print("[CorrelationsViewModel] Cache updated - timestamp: \(cacheLastUpdated!)")
        
        // Additional debug info about the cached data
        let sessionsWithHabitMetrics = cachedSleepSessions.filter { $0.habitMetrics != nil }
        print("[CorrelationsViewModel] Sessions with habitMetrics relationship: \(sessionsWithHabitMetrics.count)")
        
        if cachedSleepSessions.count > 0 {
            let scoreRange = cachedSleepSessions.compactMap { $0.sleepScore > 0 ? Int($0.sleepScore) : nil }
            if !scoreRange.isEmpty {
                let minScore = scoreRange.min() ?? 0
                let maxScore = scoreRange.max() ?? 0
                print("[CorrelationsViewModel] Sleep score range: \(minScore) - \(maxScore)")
            }
            
            // DEBUG: Print individual sleep scores and health metrics for last 10 sessions
            print("[CorrelationsViewModel] === DETAILED DATA SAMPLE (last 10 sessions) ===")
            for (index, session) in cachedSleepSessions.suffix(15).enumerated() {
                let dateStr = session.ownershipDay.formatted(date: .abbreviated, time: .omitted)
                let sleepScore = session.sleepScore
                let totalSleep = session.totalSleepTime / 3600.0 // Convert to hours
                let hrv = session.averageHRV
                let heartRate = session.averageHeartRate
                let deepSleep = session.deepDuration / 3600.0 // Convert to hours
                let remSleep = session.remDuration / 3600.0 // Convert to hours
                
                print("[\(index + 1)] \(dateStr): SleepScore=\(sleepScore), Sleep=\(String(format: "%.1f", totalSleep))h, HRV=\(String(format: "%.1f", hrv)), HR=\(String(format: "%.1f", heartRate)), Deep=\(String(format: "%.1f", deepSleep))h, REM=\(String(format: "%.1f", remSleep))h")
                
                // Also print health metrics if available
                if let metrics = session.habitMetrics {
                    let steps = metrics.steps
                    let exerciseTime = metrics.exerciseTime // Already in minutes
                    let daylightTime = metrics.timeinDaylight // Already in minutes
                    print("     Health Metrics: Steps=\(String(format: "%.0f", steps)), Exercise=\(String(format: "%.1f", exerciseTime))min, Daylight=\(String(format: "%.1f", daylightTime))min")
                } else {
                    print("     Health Metrics: MISSING RELATIONSHIP")
                }
            }
            print("[CorrelationsViewModel] === END DETAILED DATA SAMPLE ===")
        }
        
        let totalDuration = CFAbsoluteTimeGetCurrent() - methodStartTime
        print("[CorrelationsViewModel] TIMING: Total loadAndCache90DaysData() took \(String(format: "%.3f", totalDuration))s")
        print("[CorrelationsViewModel] Cached \(cachedSleepSessions.count) sleep sessions for 90 days")
    }
    
    /// Smart incremental cache update - only fetches new data
    private func updateCacheIncrementally() async throws {
        let today = calendar.startOfDay(for: Date())
        
        if let lastUpdated = cacheLastUpdated {
            let lastUpdatedDay = calendar.startOfDay(for: lastUpdated)
            
            if lastUpdatedDay == today {
                return
            }
            
            print("[CorrelationsViewModel] Incremental update: adding new days since \(lastUpdatedDay)")
            
            // 1. Add only NEW data since last update
            let newStartDate = calendar.date(byAdding: .day, value: 1, to: lastUpdatedDay) ?? today
            try await addNewDataToCache(from: newStartDate, to: today)
            
            // 2. Remove OLD data beyond 90 days
            let cutoffDate = calendar.date(byAdding: .day, value: -90, to: today) ?? today
            removeStaleDataFromCache(before: cutoffDate)
            
            print("[CorrelationsViewModel] Incremental update complete")
        } else {
            print("[CorrelationsViewModel] First time load - fetching full 90 days")
            try await loadAndCache90DaysData()
        }
        
        cacheLastUpdated = Date()
    }
    
    /// Efficiently add only new data to existing cache
    private func addNewDataToCache(from startDate: Date, to endDate: Date) async throws {
        // Fetch only NEW sleep sessions
        let sleepRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        sleepRequest.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay <= %@ AND sleepScore > 0", startDate as NSDate, endDate as NSDate)
        sleepRequest.relationshipKeyPathsForPrefetching = ["habitMetrics", "manualHabits", "workouts"]
        sleepRequest.fetchBatchSize = 20 // Smaller batch for incremental updates
        
        let newSleepSessions = try viewContext.fetch(sleepRequest)
        cachedSleepSessions.append(contentsOf: newSleepSessions)
        
        print("[CorrelationsViewModel] Added \(newSleepSessions.count) new sleep sessions")
    }
    
    /// Remove data older than 90 days from cache
    private func removeStaleDataFromCache(before cutoffDate: Date) {
        let originalSleepCount = cachedSleepSessions.count
        
        // Remove stale sleep sessions
        cachedSleepSessions.removeAll { session in
            return session.ownershipDay < cutoffDate
        }
        
        let removedSleep = originalSleepCount - cachedSleepSessions.count
        
        print("[CorrelationsViewModel] Removed \(removedSleep) stale sleep sessions")
    }
    
    /// Filters cached data based on selected time window
    private func getFilteredData() -> [SleepSessionV2] {
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) else {
            return []
        }
        
        // Filter sleep sessions
        let filteredSleepSessions = cachedSleepSessions.filter { session in
            let sessionDate = session.ownershipDay
            return sessionDate >= startDate && sessionDate <= endDate
        }
        
        return filteredSleepSessions
    }
    
    // Helper method to extract the correlation value from a sleep session based on selected metric
    private func getMetricValue(from session: SleepSessionV2, for metric: CorrelationMetric) -> Double? {
        switch metric {
        case .sleepScore:
            return session.sleepScore > 0 ? session.sleepScore : nil
        case .sleepDuration:
            return session.totalSleepTime > 0 ? session.totalSleepTime / 3600.0 : nil // Convert to hours
        case .totalAwakeTime:
            return session.totalAwakeTime >= 0 ? session.totalAwakeTime / 3600.0 : nil // Convert to hours
        case .hrv:
            return session.averageHRV > 0 ? session.averageHRV : nil
        case .heartRate:
            return session.averageHeartRate > 0 ? session.averageHeartRate : nil
        case .deepSleep:
            return session.deepDuration > 0 ? session.deepDuration / 3600.0 : nil // Convert to hours
        case .remSleep:
            return session.remDuration > 0 ? session.remDuration / 3600.0 : nil // Convert to hours
        }
    }

    // New method to compute all regression insights
    func calculateAllRegressionInsights() {
        isLoading = true
        errorMessage = nil
        regressionInsights = []

        Task(priority: .userInitiated) {
            do {
                try await self.updateCacheIncrementally()
                let sleepSessions = self.getFilteredData()

                // Check if we have enough data for regression
                if sleepSessions.count < 30 {
                    await MainActor.run {
                        self.baselineProgress = (current: sleepSessions.count, required: 30)
                        self.regressionInsights = []
                        self.sleepMetricGroups = []
                        self.isLoading = false
                    }
                    return
                } else {
                    await MainActor.run {
                        self.baselineProgress = nil
                    }
                }

                var allInsights: [RegressionInsight] = []

                // For each sleep metric, perform regression analysis
                for sleepMetric in CorrelationMetric.allCases {
                    let insights = await self.performRegressionAnalysis(
                        for: sleepMetric,
                        sessions: sleepSessions
                    )
                    allInsights.append(contentsOf: insights)
                    print("[DEBUG] After \(sleepMetric.displayName): total insights = \(allInsights.count)")
                }

                print("[DEBUG] Total insights generated: \(allInsights.count)")
                if !allInsights.isEmpty {
                    let samplePValues = allInsights.prefix(5).map { $0.pValue }
                    print("[DEBUG] Sample p-values: \(samplePValues)")
                } else {
                    print("[DEBUG] Sample p-values: []")
                }

                // Group insights by sleep metric and sort within each group
                print("[DEBUG] Total insights generated: \(allInsights.count)")
                print("[DEBUG] Sample p-values: \(allInsights.prefix(5).map { $0.pValue })")
                let groupedInsights = Dictionary(grouping: allInsights.filter { $0.pValue < 0.99 && !$0.pValue.isNaN && $0.pValue.isFinite }) { $0.sleepMetricName }

                var metricGroups: [SleepMetricGroup] = []
                for (sleepMetricName, insights) in groupedInsights {
                    // Find the corresponding CorrelationMetric
                    guard let sleepMetric = CorrelationMetric.allCases.first(where: { $0.displayName == sleepMetricName }) else { continue }

                    // Sort by impact significance (p-value) and split into top 3 and additional
                    let sortedInsights = insights.sorted { $0.pValue < $1.pValue }
                    let topInsights = Array(sortedInsights.prefix(3))
                    let additionalInsights = Array(sortedInsights.dropFirst(3))

                    metricGroups.append(SleepMetricGroup(
                        sleepMetric: sleepMetric,
                        topInsights: topInsights,
                        additionalInsights: additionalInsights
                    ))
                }

                // Sort groups by the best p-value in their top insights
                let sortedGroups = metricGroups.sorted { group1, group2 in
                    let bestP1 = group1.topInsights.first?.pValue ?? 1.0
                    let bestP2 = group2.topInsights.first?.pValue ?? 1.0
                    return bestP1 < bestP2
                }

                await MainActor.run {
                    self.cachedInsights = Array(allInsights.filter { $0.pValue < 0.99 && !$0.pValue.isNaN && $0.pValue.isFinite }.sorted { $0.pValue < $1.pValue }.prefix(20))
                    self.insightsLastUpdated = Date()
                    self.regressionInsights = self.cachedInsights
                    self.sleepMetricGroups = sortedGroups
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to compute regression insights: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    // Method to toggle expanded state of a sleep metric group
    func toggleGroupExpansion(_ groupId: UUID) {
        if let index = sleepMetricGroups.firstIndex(where: { $0.id == groupId }) {
            sleepMetricGroups[index].isExpanded.toggle()
        }
    }
    
    // Perform regression analysis for a specific sleep metric
    private func performRegressionAnalysis(
        for sleepMetric: CorrelationMetric,
        sessions: [SleepSessionV2]
    ) async -> [RegressionInsight] {
        var insights: [RegressionInsight] = []

        // Extract sleep metric values (dependent variable)
        var sleepValues = sessions.compactMap { getMetricValue(from: $0, for: sleepMetric) }

        print("[DEBUG] Sleep metric: \(sleepMetric.displayName), sleep values count: \(sleepValues.count)")

        guard sleepValues.count >= 30 else { 
            print("[DEBUG] Not enough sleep values for \(sleepMetric.displayName): \(sleepValues.count) < 30")
            return [] 
        }

        // Apply min-max scaling to sleep values to match health metric scaling
        sleepValues = minMaxScale(sleepValues)
        
        print("[DEBUG] Sleep metric: \(sleepMetric.displayName), sleep values count: \(sleepValues.count) (scaled to 0-1)")

        // Prepare health metrics data (independent variables)
        var healthMetricsData: [[Double]] = []
        var healthMetricNames: [String] = []
        var healthMetricIcons: [String] = []

        // Add continuous health metrics
        for healthMetric in ["Exercise Time", "Steps", "Time in Daylight"] {
            let data = extractData(for: healthMetric, sleepMetric: sleepMetric, sessions: sessions)
            print("[DEBUG] Health metric: \(healthMetric), data points: \(data.count)")
            
            let nonZeroCount = data.filter { $0.healthValue > 0 }.count
            if data.count == sleepValues.count && nonZeroCount >= 7 { // Require at least 7 non-zero values
                var scaledData = data.map { $0.healthValue }
                scaledData = minMaxScale(scaledData) // Apply min-max scaling
                healthMetricsData.append(scaledData)
                healthMetricNames.append(healthMetric)
                healthMetricIcons.append(iconForHealthMetric(healthMetric))
                print("[DEBUG] ✓ Added \(healthMetric) to regression (\(data.count) total, \(nonZeroCount) non-zero)")
            } else {
                print("[DEBUG] ✗ Skipped \(healthMetric): insufficient logged data (\(nonZeroCount) non-zero, need >= 7)")
            }
        }

        // Add workout data (summed by type)
        let workoutData = await extractWorkoutData(for: sleepMetric, sessions: sessions)
        for (workoutType, data) in workoutData {
            let nonZeroCount = data.filter { $0.healthValue > 0 }.count
            if data.count == sleepValues.count && nonZeroCount >= 7 { // Require at least 7 non-zero values
                var scaledData = data.map { $0.healthValue }
                scaledData = minMaxScale(scaledData) // Apply min-max scaling
                healthMetricsData.append(scaledData)
                healthMetricNames.append(workoutType)
                healthMetricIcons.append(iconForWorkoutType(workoutType))
                print("[DEBUG] ✓ Added workout \(workoutType) to regression (\(data.count) total, \(nonZeroCount) non-zero)")
            } else {
                print("[DEBUG] ✗ Skipped workout \(workoutType): insufficient logged data (\(nonZeroCount) non-zero, need >= 7)")
            }
        }

        // Add habit data
        let habitData = await extractHabitData(for: sleepMetric, sessions: sessions)
        for (habitName, data) in habitData {
            let nonZeroCount = data.filter { $0.healthValue > 0 }.count
            if data.count == sleepValues.count && nonZeroCount >= 7 { // Require at least 7 non-zero values
                var scaledData = data.map { $0.healthValue }
                scaledData = minMaxScale(scaledData) // Apply min-max scaling
                healthMetricsData.append(scaledData)
                healthMetricNames.append(habitName)
                healthMetricIcons.append("checkmark.circle.fill")
                print("[DEBUG] ✓ Added habit \(habitName) to regression (\(data.count) total, \(nonZeroCount) non-zero)")
            } else {
                print("[DEBUG] ✗ Skipped habit \(habitName): insufficient logged data (\(nonZeroCount) non-zero, need >= 7)")
            }
        }

        guard !healthMetricsData.isEmpty else { 
            print("[DEBUG] No health metrics data available for \(sleepMetric.displayName)")
            return [] 
        }

        print("[DEBUG] Performing regression for \(sleepMetric.displayName) with \(healthMetricsData.count) health metrics")
        print("[DEBUG] Sleep values count: \(sleepValues.count) (scaled 0-1)")
        for (i, healthData) in healthMetricsData.enumerated() {
            print("[DEBUG] Health metric \(i) (\(healthMetricNames[i])): \(healthData.count) data points (scaled 0-1)")
        }

        // All health metrics should now have the same length as sleep values
        // Perform regression with the full dataset
        let regressionResults = RegressionEngine.performRegression(
            dependent: sleepValues,
            independents: healthMetricsData
        )

        print("[DEBUG] Regression results count: \(regressionResults.count)")

        // Skip intercept (first result)
        let predictorResults = Array(regressionResults.dropFirst())

        print("[DEBUG] Predictor results count: \(predictorResults.count)")

        // Generate insights for each predictor
        for (index, result) in predictorResults.enumerated() {
            let healthMetricName = healthMetricNames[index]
            let healthMetricIcon = healthMetricIcons[index]

            print("[DEBUG] Processing result \(index): \(healthMetricName), p-value: \(result.pValue)")
            
            // For scaled data, the coefficient represents the change in sleep metric (as fraction of its range)
            // per unit change in health metric (as fraction of its range)
            // Convert to a more interpretable percentage impact
            let percentageImpact = result.coefficient * 100 // Convert to percentage
            
            print("[DEBUG] \(healthMetricName): coeff=\(String(format: "%.6f", result.coefficient)), percentage_impact=\(String(format: "%.3f", percentageImpact))%")

            // Generate user-friendly description based on percentage impact
            let impactDescription = generateImpactDescription(
                coefficient: result.coefficient,
                healthMetric: healthMetricName,
                sleepMetric: sleepMetric
            )

            let confidenceLevel = ConfidenceLevel.fromPValue(result.pValue)

            // Create bin analysis for drill-down (keep existing functionality)
            var data: [(healthValue: Double, sleepValue: Double)] = []
            
            // Collect workout types and habit names dynamically to determine extraction method
            var workoutTypes = Set<String>()
            var habitNames = Set<String>()
            
            // Get workout types
            for session in sessions {
                if let workouts = session.workouts?.allObjects as? [Workout] {
                    for workout in workouts {
                        workoutTypes.insert(workout.workoutType)
                    }
                }
            }
            
            // Get manually tracked habit names
            let habitDefinitions = try? viewContext.fetch(NSFetchRequest<HabitDefinition>(entityName: "HabitDefinition"))
            habitDefinitions?.forEach { habitNames.insert($0.name) }
            
            // Choose appropriate data extraction method
            if workoutTypes.contains(healthMetricName) {
                // For workout types, extract data using workout-specific method
                let workoutData = await extractWorkoutData(for: sleepMetric, sessions: sessions)
                data = workoutData[healthMetricName] ?? []
            } else if habitNames.contains(healthMetricName) {
                // For manually tracked habits, extract data using habit-specific method
                let habitData = await extractHabitData(for: sleepMetric, sessions: sessions)
                data = habitData[healthMetricName] ?? []
            } else {
                // For regular health metrics, use the standard extraction
                data = extractData(for: healthMetricName, sleepMetric: sleepMetric, sessions: sessions)
            }
            
            let binResult = await createBinAnalysis(
                healthMetricName: healthMetricName,
                healthMetricIcon: healthMetricIcon,
                sleepMetricName: sleepMetric.displayName,
                data: data,
                unit: unitForHealthMetric(healthMetricName, habitNames: habitNames)
            )

            let nonZeroCount = data.filter { $0.healthValue > 0 }.count
            
            let insight = RegressionInsight(
                healthMetricName: healthMetricName,
                healthMetricIcon: healthMetricIcon,
                sleepMetricName: sleepMetric.displayName,
                sleepMetricIcon: sleepMetric.icon,
                coefficient: result.coefficient,
                absoluteImpact: percentageImpact, // Use percentage impact instead of inflated absolute value
                pValue: result.pValue,
                confidenceInterval: result.confidenceInterval,
                impactDescription: impactDescription,
                confidenceLevel: confidenceLevel,
                sampleSize: nonZeroCount, // Use non-zero observations count instead of total data points
                binAnalysisResult: binResult
            )

            insights.append(insight)
        }

        print("[DEBUG] Generated \(insights.count) insights for \(sleepMetric.displayName)")
        return insights
    }
    
    // Helper method to extract data for a specific health metric
    private func extractData(for healthMetric: String, sleepMetric: CorrelationMetric, sessions: [SleepSessionV2]) -> [(healthValue: Double, sleepValue: Double)] {
        var data: [(healthValue: Double, sleepValue: Double)] = []
        var validSleepCount = 0
        var loggedHealthCount = 0 // Actually logged (non-nil) values
        var nonZeroHealthCount = 0 // Non-zero values
        
        for session in sessions {
            guard let sleepValue = getMetricValue(from: session, for: sleepMetric) else { continue }
            validSleepCount += 1
            
            var healthValue: Double = 0 // Default to 0 for missing data
            var isLogged = false
            
            switch healthMetric {
            case "Exercise Time":
                if let exerciseTime = session.habitMetrics?.exerciseTime {
                    healthValue = exerciseTime
                    isLogged = true
                }
            case "Steps":
                if let steps = session.habitMetrics?.steps {
                    healthValue = steps
                    isLogged = true
                }
            case "Time in Daylight":
                if let daylight = session.habitMetrics?.timeinDaylight {
                    healthValue = daylight
                    isLogged = true
                }
            default:
                // Handle workout types by checking if this healthMetric matches a workout type
                if let workouts = session.workouts?.allObjects as? [Workout] {
                    for workout in workouts {
                        if workout.workoutType == healthMetric {
                            healthValue = workout.durationInMinutes
                            isLogged = true
                            break
                        }
                    }
                }
            }
            
            // Include ALL sessions with valid sleep data, using 0 for unlogged metrics
            data.append((healthValue: healthValue, sleepValue: sleepValue))
            if isLogged {
                loggedHealthCount += 1
                if healthValue > 0 {
                    nonZeroHealthCount += 1
                }
            }
        }
        
        print("[DEBUG] \(healthMetric): sessions=\(sessions.count), valid_sleep=\(validSleepCount), logged_health=\(loggedHealthCount), non_zero=\(nonZeroHealthCount), final_data=\(data.count)")
        return data
    }
    
    // Helper method to extract workout data by type
    private func extractWorkoutData(for sleepMetric: CorrelationMetric, sessions: [SleepSessionV2]) async -> [String: [(healthValue: Double, sleepValue: Double)]] {
        var workoutData: [String: [(healthValue: Double, sleepValue: Double)]] = [:]
        
        // First, collect all unique workout types that have been logged
        var allWorkoutTypes = Set<String>()
        for session in sessions {
            if let workouts = session.workouts?.allObjects as? [Workout] {
                for workout in workouts {
                    allWorkoutTypes.insert(workout.workoutType)
                }
            }
        }
        
        // Initialize data arrays for each workout type
        for workoutType in allWorkoutTypes {
            workoutData[workoutType] = []
        }
        
        // Fill data for each session
        for session in sessions {
            guard let sleepValue = getMetricValue(from: session, for: sleepMetric) else { continue }
            
            // Get workout durations for this session
            var dailyWorkoutDurations: [String: Double] = [:]
            if let workouts = session.workouts?.allObjects as? [Workout] {
                for workout in workouts {
                    let workoutType = workout.workoutType
                    let durationMinutes = workout.durationInMinutes
                    dailyWorkoutDurations[workoutType, default: 0] += durationMinutes
                }
            }
            
            // Add data points for each workout type (0 if not done that day)
            for workoutType in allWorkoutTypes {
                let duration = dailyWorkoutDurations[workoutType] ?? 0
                workoutData[workoutType]?.append((healthValue: duration, sleepValue: sleepValue))
            }
        }
        
        return workoutData
    }
    
    // Helper method to extract habit data
    private func extractHabitData(for sleepMetric: CorrelationMetric, sessions: [SleepSessionV2]) async -> [String: [(healthValue: Double, sleepValue: Double)]] {
        var habitData: [String: [(healthValue: Double, sleepValue: Double)]] = [:]
        
        return await viewContext.perform { [weak self] in
            guard let self = self else { return [:] }
            
            do {
                // Fetch all manually tracked habit definitions
                let habitsFetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                habitsFetchRequest.predicate = NSPredicate(format: "isArchived == NO")
                let habitDefinitions = try self.viewContext.fetch(habitsFetchRequest)
                
                for habitDefinition in habitDefinitions {
                    var data: [(healthValue: Double, sleepValue: Double)] = []
                    
                    for session in sessions {
                        guard let sleepValue = self.getMetricValue(from: session, for: sleepMetric) else { continue }
                        
                        // Check if this habit was completed on this day
                        let habitRecordsForSession = session.manualHabits?.allObjects as? [HabitRecord] ?? []
                        let habitCompleted = habitRecordsForSession.contains { record in
                            record.definition == habitDefinition
                        }
                        
                        // Use 1.0 for completed, 0.0 for not completed
                        let healthValue = habitCompleted ? 1.0 : 0.0
                        data.append((healthValue: healthValue, sleepValue: sleepValue))
                    }
                    
                    if data.count == sessions.count { // Include all habits, they'll be filtered later if needed
                        habitData[habitDefinition.name] = data
                    }
                }
                
                return habitData
                
            } catch {
                print("[CorrelationsViewModel] Error extracting habit data: \(error)")
                return [:]
            }
        }
    }
    
    // Helper to calculate Pearson correlation coefficient
    private func calculatePearsonCorrelation(data: [(healthValue: Double, sleepValue: Double)]) -> Double {
        guard data.count >= 2 else { return 0 }
        
        let healthValues = data.map { $0.healthValue }
        let sleepValues = data.map { $0.sleepValue }
        
        let healthMean = healthValues.reduce(0, +) / Double(healthValues.count)
        let sleepMean = sleepValues.reduce(0, +) / Double(sleepValues.count)
        
        var numerator: Double = 0
        var healthDenom: Double = 0
        var sleepDenom: Double = 0
        
        for i in 0..<data.count {
            let healthDiff = healthValues[i] - healthMean
            let sleepDiff = sleepValues[i] - sleepMean
            
            numerator += healthDiff * sleepDiff
            healthDenom += healthDiff * healthDiff
            sleepDenom += sleepDiff * sleepDiff
        }
        
        let denominator = sqrt(healthDenom * sleepDenom)
        return denominator == 0 ? 0 : numerator / denominator
    }
    
    // Helper to calculate mean difference for binary variables
    private func calculateMeanDifference(data: [(healthValue: Double, sleepValue: Double)]) -> Double {
        guard data.count >= 2 else { return 0 }
        
        // Assume binary variable (0 or 1, or low/high threshold)
        let threshold = (data.map { $0.healthValue }.min()! + data.map { $0.healthValue }.max()!) / 2
        
        let group1 = data.filter { $0.healthValue <= threshold }.map { $0.sleepValue }
        let group2 = data.filter { $0.healthValue > threshold }.map { $0.sleepValue }
        
        guard !group1.isEmpty && !group2.isEmpty else { return 0 }
        
        let mean1 = group1.reduce(0, +) / Double(group1.count)
        let mean2 = group2.reduce(0, +) / Double(group2.count)
        
        return mean2 - mean1 // Group 2 minus Group 1 (higher health value minus lower)
    }
    
    // Helper to compute percentage change (direction-consistent with correlation)
    private func computePercentageChange(for result: BinAnalysisResult, sleepMetric: CorrelationMetric, correlationCoefficient: Double) -> Double {
        guard result.isValid, !result.bins.isEmpty else { return 0 }
        
        // Choose bin based on correlation direction and sleep metric preferences
        let targetBinAvg: Double
        
        if correlationCoefficient >= 0 {
            // Positive correlation - higher health values should give better sleep
            switch sleepMetric {
            case .totalAwakeTime, .heartRate:
                // Lower is better for these metrics - use LOWEST health value bin
                targetBinAvg = result.bins.min(by: { $0.averageSleepMetric < $1.averageSleepMetric })?.averageSleepMetric ?? result.baseline
            default:
                // Higher is better - use HIGHEST health value bin
                targetBinAvg = result.bins.max(by: { $0.averageSleepMetric < $1.averageSleepMetric })?.averageSleepMetric ?? result.baseline
            }
        } else {
            // Negative correlation - higher health values give worse sleep
            switch sleepMetric {
            case .totalAwakeTime, .heartRate:
                // Lower is better - use HIGHEST health value bin (counterintuitive but consistent)
                targetBinAvg = result.bins.max(by: { $0.averageSleepMetric < $1.averageSleepMetric })?.averageSleepMetric ?? result.baseline
            default:
                // Higher is better - use LOWEST health value bin
                targetBinAvg = result.bins.min(by: { $0.averageSleepMetric < $1.averageSleepMetric })?.averageSleepMetric ?? result.baseline
            }
        }
        
        let rawPercentage = ((targetBinAvg - result.baseline) / result.baseline) * 100
        
        // Apply direction correction for "lower is better" metrics
        switch sleepMetric {
        case .totalAwakeTime, .heartRate:
            return -rawPercentage // Invert so improvements show as positive
        default:
            return rawPercentage
        }
    }
    
    // Helper to adjust percentage based on good direction for each metric
    private func adjustPercentageForGoodDirection(_ rawPercentage: Double, sleepMetric: CorrelationMetric) -> Double {
        // For metrics where lower values are better, invert the percentage
        // so that improvements show as positive values
        switch sleepMetric {
        case .totalAwakeTime, .heartRate:
            // Lower is better - invert the percentage
            return -rawPercentage
        default:
            // Higher is better - keep the percentage as-is
            return rawPercentage
        }
    }
    
    // Helpers for icons and units
    private func iconForHealthMetric(_ name: String) -> String {
        switch name {
        case "Exercise Time": return "figure.run"
        case "Steps": return "figure.walk"
        case "Time in Daylight": return "sun.max.fill"
        default: return "chart.bar"
        }
    }
    
    private func unitForHealthMetric(_ name: String, habitNames: Set<String> = []) -> String {
        switch name {
        case "Steps": return "steps"
        default:
            // Check if this is a manually tracked habit
            if habitNames.contains(name) {
                return "completed"
            }
            return "min"
        }
    }

    /// Apply filtering to results based on user selections
    private func applyFiltering(to results: [BinAnalysisResult]) -> [BinAnalysisResult] {
        var filteredResults: [BinAnalysisResult] = []
        
        // Filter health metrics (each gets its own chart)
        let healthMetricNames = ["Exercise Time", "Steps", "Time in Daylight"]
        for result in results {
            if healthMetricNames.contains(result.healthMetricName) {
                // Only include if this health metric is visible
                if visibleHealthMetrics.contains(result.healthMetricName) {
                    filteredResults.append(result)
                }
            } else if availableWorkoutTypes.contains(result.healthMetricName) {
                // This is a workout type result - check if it's visible
                if visibleWorkoutTypes.contains(result.healthMetricName) {
                    filteredResults.append(result)
                }
            } else {
                // This is a manually tracked habits result - handle filtering within the single chart
                if availableHabitNames.isEmpty {
                    // No habits available yet, show the original result
                    filteredResults.append(result)
                } else if visibleHabitNames.isEmpty {
                    // All habits deselected - show no data (don't add this result)
                    // This will cause the chart to not appear, showing the "no data" state
                    continue
                } else {
                    // Filter the bins within this result to only show visible habits
                    let filteredBins = result.bins.filter { bin in
                        visibleHabitNames.contains(bin.range)
                    }
                    
                    if !filteredBins.isEmpty {
                        // Create a new result with filtered bins
                        let filteredResult = BinAnalysisResult(
                            healthMetricName: result.healthMetricName,
                            healthMetricIcon: result.healthMetricIcon,
                            sleepMetricName: result.sleepMetricName,
                            bins: filteredBins,
                            totalSamples: filteredBins.reduce(0) { $0 + $1.sampleCount },
                            status: result.status,
                            baseline: result.baseline
                        )
                        filteredResults.append(filteredResult)
                    }
                    // If filteredBins is empty, we don't add the result (no data state)
                }
            }
        }
        
        return filteredResults
    }
    
    /// Creates flexible bins for a health metric with dynamic bin count and inclusive boundaries
    private func createBinAnalysis(
        healthMetricName: String,
        healthMetricIcon: String,
        sleepMetricName: String,
        data: [(healthValue: Double, sleepValue: Double)],
        unit: String
    ) async -> BinAnalysisResult {
        
        // Check if we have enough data points
        let minDataPoints = 7  // Reduced from 10 to allow smaller datasets
        guard data.count >= minDataPoints else {
            print("[DEBUG] Insufficient data: \(data.count) < \(minDataPoints)")
            return BinAnalysisResult(
                healthMetricName: healthMetricName,
                healthMetricIcon: healthMetricIcon,
                sleepMetricName: sleepMetricName,
                bins: [],
                totalSamples: data.count,
                status: .insufficientData(current: data.count, required: minDataPoints),
                baseline: 0.0
            )
        }
        
        // Calculate baseline (average sleep metric for this time window)
        let baseline = data.map { $0.sleepValue }.reduce(0, +) / Double(data.count)
        
        let bins = createFlexibleBins(data: data, unit: unit)
        
        return BinAnalysisResult(
            healthMetricName: healthMetricName,
            healthMetricIcon: healthMetricIcon,
            sleepMetricName: sleepMetricName,
            bins: bins,
            totalSamples: data.count,
            status: .valid,
            baseline: baseline
        )
    }
    
    /// Creates flexible bins based on data distribution with minimum 3 samples per bin
    private func createFlexibleBins(data: [(healthValue: Double, sleepValue: Double)], unit: String) -> [HealthMetricBin] {
        guard !data.isEmpty else { return [] }
        
        print("[DEBUG] Creating bins for \(data.count) data points with unit: \(unit)")
        
        // Special handling for binary data (manually tracked habits)
        if unit == "completed" {
            return createBinaryBins(data: data)
        }
        
        // Sort data by health metric value
        let sortedData = data.sorted { $0.healthValue < $1.healthValue }
        let healthValues = sortedData.map { $0.healthValue }
        
        let minValue = healthValues.first!
        let maxValue = healthValues.last!
        
        print("[DEBUG] Health metric range: \(minValue) to \(maxValue)")
        
        // Handle edge case where all values are the same
        guard minValue < maxValue else {
            print("[DEBUG] All values are the same, creating single bin")
            let averageSleep = sortedData.map { $0.sleepValue }.reduce(0, +) / Double(sortedData.count)
            return [HealthMetricBin(
                range: formatRange(lower: minValue, upper: maxValue, unit: unit),
                lowerBound: minValue,
                upperBound: maxValue,
                averageSleepMetric: averageSleep,
                sampleCount: sortedData.count
            )]
        }
        
        // More realistic bin count based on actual data size
        let targetBinCount: Int
        if data.count <= 6 {
            targetBinCount = 2 // Low/High only for very small datasets
        } else if data.count <= 15 {
            targetBinCount = 3 // Low/Medium/High for small datasets  
        } else if data.count <= 30 {
            targetBinCount = 4 // More granular for medium datasets
        } else if data.count <= 50 {
            targetBinCount = 5 // Fine-grained for larger datasets
        } else {
            targetBinCount = 6 // Maximum granularity for large datasets
        }
        
        print("[DEBUG] Target bin count: \(targetBinCount) for \(data.count) samples")
        
        // Calculate initial bin boundaries
        let range = maxValue - minValue
        let binWidth = range / Double(targetBinCount)
        
        var bins: [HealthMetricBin] = []
        var dataIndex = 0
        
        for i in 0..<targetBinCount {
            let lowerBound = minValue + Double(i) * binWidth
            let upperBound = i == targetBinCount - 1 ? maxValue : minValue + Double(i + 1) * binWidth
            
            // Find data points in this bin (inclusive boundaries)
            var binData: [(healthValue: Double, sleepValue: Double)] = []
            
            while dataIndex < sortedData.count {
                let point = sortedData[dataIndex]
                if point.healthValue >= lowerBound && point.healthValue <= upperBound {
                    binData.append(point)
                    dataIndex += 1
                } else if point.healthValue > upperBound {
                    break // Move to next bin
                } else {
                    dataIndex += 1 // Skip points below current bin
                }
            }
            
            // Reset index for overlapping boundaries
            if i < targetBinCount - 1 {
                dataIndex = sortedData.firstIndex { $0.healthValue > upperBound } ?? sortedData.count
            }
            
            print("[DEBUG] Bin \(i + 1): \(formatRange(lower: lowerBound, upper: upperBound, unit: unit)) has \(binData.count) samples")
            
            // Create bin even if it has low sample count - show all data to user
            if binData.count > 0 {
                let averageSleep = binData.map { $0.sleepValue }.reduce(0, +) / Double(binData.count)
                bins.append(HealthMetricBin(
                    range: formatRange(lower: lowerBound, upper: upperBound, unit: unit),
                    lowerBound: lowerBound,
                    upperBound: upperBound,
                    averageSleepMetric: averageSleep,
                    sampleCount: binData.count
                ))
                print("[DEBUG] ✅ Bin added with \(binData.count) samples, avg sleep: \(String(format: "%.1f", averageSleep))")
            } else {
                print("[DEBUG] ❌ Bin skipped - empty bin")
            }
        }
        
        print("[DEBUG] Initial binning created \(bins.count) valid bins")
        
        print("[DEBUG] Final result: \(bins.count) bins for \(data.count) samples")
        return bins
    }
    
    /// Creates binary bins for manually tracked habits (Completed/Not Completed)
    private func createBinaryBins(data: [(healthValue: Double, sleepValue: Double)]) -> [HealthMetricBin] {
        print("[DEBUG] Creating binary bins for manually tracked habits")
        
        // Separate data into completed (≥ 0.5) and not completed (< 0.5)
        let completedData = data.filter { $0.healthValue >= 0.5 }
        let notCompletedData = data.filter { $0.healthValue < 0.5 }
        
        var bins: [HealthMetricBin] = []
        
        // Create "Not Completed" bin
        if !notCompletedData.isEmpty {
            let averageSleep = notCompletedData.map { $0.sleepValue }.reduce(0, +) / Double(notCompletedData.count)
            bins.append(HealthMetricBin(
                range: "Not Completed",
                lowerBound: 0.0,
                upperBound: 0.5,
                averageSleepMetric: averageSleep,
                sampleCount: notCompletedData.count
            ))
            print("[DEBUG] Not Completed bin: \(notCompletedData.count) samples, avg sleep: \(String(format: "%.2f", averageSleep))")
        }
        
        // Create "Completed" bin
        if !completedData.isEmpty {
            let averageSleep = completedData.map { $0.sleepValue }.reduce(0, +) / Double(completedData.count)
            bins.append(HealthMetricBin(
                range: "Completed",
                lowerBound: 0.5,
                upperBound: 1.0,
                averageSleepMetric: averageSleep,
                sampleCount: completedData.count
            ))
            print("[DEBUG] Completed bin: \(completedData.count) samples, avg sleep: \(String(format: "%.2f", averageSleep))")
        }
        
        return bins
    }
    
    /// Redistributes data into a target number of bins ensuring minimum samples per bin
    private func redistributeIntoBins(data: [(healthValue: Double, sleepValue: Double)], targetBins: Int, unit: String) -> [HealthMetricBin] {
        let minSamplesPerBin = 3
        let totalSamples = data.count
        
        // Calculate actual bin count based on available data
        let actualBinCount = min(targetBins, totalSamples / minSamplesPerBin)
        guard actualBinCount > 0 else { return [] }
        
        let samplesPerBin = totalSamples / actualBinCount
        let extraSamples = totalSamples % actualBinCount
        
        var bins: [HealthMetricBin] = []
        var startIndex = 0
        
        for i in 0..<actualBinCount {
            let binSize = samplesPerBin + (i < extraSamples ? 1 : 0)
            let endIndex = min(startIndex + binSize, totalSamples)
            
            let binData = Array(data[startIndex..<endIndex])
            guard !binData.isEmpty else { continue }
            
            let lowerBound = binData.first!.healthValue
            let upperBound = binData.last!.healthValue
            let averageSleep = binData.map { $0.sleepValue }.reduce(0, +) / Double(binData.count)
            
            bins.append(HealthMetricBin(
                range: formatRange(lower: lowerBound, upper: upperBound, unit: unit),
                lowerBound: lowerBound,
                upperBound: upperBound,
                averageSleepMetric: averageSleep,
                sampleCount: binData.count
            ))
            
            startIndex = endIndex
        }
        
        return bins
    }
    
    /// Formats a range string for display
    private func formatRange(lower: Double, upper: Double, unit: String) -> String {
        // Special handling for manually tracked habits (binary 0-1 values)
        if unit == "completed" {
            if lower == 0.0 && upper == 0.5 {
                return "Not Completed"
            } else if lower == 0.5 && upper == 1.0 {
                return "Completed"
            } else {
                // For any other binary ranges, determine based on midpoint
                let midpoint = (lower + upper) / 2.0
                return midpoint < 0.5 ? "Not Completed" : "Completed"
            }
        }

        // Standard formatting for other metrics
        if unit == "steps" {
            return "\(Int(lower))-\(Int(upper)) steps"
        } else {
            return "\(Int(lower))-\(Int(upper)) \(unit)"
        }
    }

    /// Creates a single combined analysis for all manually tracked habits (one bar per habit)
    private func createManuallyTrackedHabitsAnalyses(
        sleepSessions: [SleepSessionV2],
        sleepMetric: CorrelationMetric
    ) async -> [BinAnalysisResult] {
        
        return await viewContext.perform { [weak self] in
            guard let self = self else { return [] }
            
            do {
                // Fetch all manually tracked habit definitions (not archived)
                let habitsFetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                habitsFetchRequest.predicate = NSPredicate(format: "isArchived == NO")
                habitsFetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                let habitDefinitions = try self.viewContext.fetch(habitsFetchRequest)
                
                // Early exit if no manually tracked habits exist
                guard !habitDefinitions.isEmpty else {
                    print("[CorrelationsViewModel] No manually tracked habits found")
                    return []
                }
                
                print("[CorrelationsViewModel] Found \(habitDefinitions.count) manually tracked habits: \(habitDefinitions.map { $0.name }.joined(separator: ", "))")
                
                // Calculate baseline from ALL sleep sessions in the time window (proper comparison baseline)
                let allSleepValues = sleepSessions.compactMap { session in
                    self.getMetricValue(from: session, for: sleepMetric)
                }
                guard !allSleepValues.isEmpty else {
                    print("[CorrelationsViewModel] No sleep data available for baseline calculation")
                    return []
                }
                let overallBaseline = allSleepValues.reduce(0, +) / Double(allSleepValues.count)
                print("[CorrelationsViewModel] Calculated baseline from \(allSleepValues.count) total sleep sessions: \(String(format: "%.1f", overallBaseline))")
                
                // Calculate completion impact for each habit
                var habitImpacts: [(name: String, icon: String, averageImpact: Double, totalData: Int)] = []
                
                for habitDefinition in habitDefinitions {
                    var habitData: [(habitCompleted: Bool, sleepValue: Double)] = []
                    
                    for session in sleepSessions {
                        guard let metricValue = self.getMetricValue(from: session, for: sleepMetric) else { continue }
                        
                        // Look for this specific habit from the session's manualHabits relationship
                        let habitRecordsForSession = session.manualHabits?.allObjects as? [HabitRecord] ?? []
                        let habitCompleted = habitRecordsForSession.contains { record in
                            record.definition == habitDefinition
                        }
                        
                        habitData.append((habitCompleted: habitCompleted, sleepValue: metricValue))
                    }
                    print("[CorrelationsViewModel] Generated \(habitData.count) data points for habit '\(habitDefinition.name)'")
                    
                    // Check minimum data requirements
                    let minDataPoints = 7
                    guard habitData.count >= minDataPoints else {
                        print("[CorrelationsViewModel] Insufficient data for habit '\(habitDefinition.name)': \(habitData.count) < \(minDataPoints)")
                        continue
                    }
                    
                    // Calculate impact: completed days vs not completed days
                    let completedData = habitData.filter { $0.habitCompleted }
                    guard !completedData.isEmpty else { continue } // Only include habits with at least some completion data
                    
                    print("[CorrelationsViewModel] Habit '\(habitDefinition.name)' has \(completedData.count) completed days out of \(habitData.count) total days")
                    
                    let averageCompleted = completedData.map { $0.sleepValue }.reduce(0, +) / Double(completedData.count)
                    
                    habitImpacts.append((
                        name: habitDefinition.name,
                        icon: habitDefinition.icon,
                        averageImpact: averageCompleted,
                        totalData: completedData.count  // Only count days when habit was actually completed
                    ))
                }
                
                // Early exit if no habits have sufficient data
                guard !habitImpacts.isEmpty else {
                    print("[CorrelationsViewModel] No manually tracked habits have sufficient data")
                    return []
                }
                
                // Create bins (one per habit that has data)
                var bins: [HealthMetricBin] = []
                let totalSampleCount = habitImpacts.reduce(0) { $0 + $1.totalData }
                
                // Update available habit names on main actor
                let habitNames = habitImpacts.map { $0.name }
                Task { @MainActor in
                    self.availableHabitNames = habitNames
                    // Initialize visible habits to show all by default
                    if self.visibleHabitNames.isEmpty {
                        self.visibleHabitNames = Set(habitNames)
                    }
                }
                
                for impact in habitImpacts {
                    bins.append(HealthMetricBin(
                        range: impact.name,
                        lowerBound: 0.0,
                        upperBound: 1.0,
                        averageSleepMetric: impact.averageImpact,
                        sampleCount: impact.totalData
                    ))
                }
                
                // Create single combined result
                let result = BinAnalysisResult(
                    healthMetricName: "Manually Tracked Habits",
                    healthMetricIcon: "checkmark.circle.fill",
                    sleepMetricName: sleepMetric.displayName,
                    bins: bins,
                    totalSamples: totalSampleCount,
                    status: .valid,
                    baseline: overallBaseline
                )
                
                print("[CorrelationsViewModel] Created combined habits analysis with \(bins.count) habit bars, \(totalSampleCount) total samples")
                print("[CorrelationsViewModel] Baseline calculated from all \(allSleepValues.count) sleep sessions: \(String(format: "%.1f", overallBaseline))")
                
                return [result]
                
            } catch {
                print("[CorrelationsViewModel] Error creating manually tracked habits analyses: \(error)")
                return []
            }
        }
    }
    
    // Updated createWorkoutAnalyses to return summaries
    private func createWorkoutSummaries(for sleepMetric: CorrelationMetric, sessions: [SleepSessionV2]) async -> [CorrelationSummary] {
        // Group workouts by type and sum durations per day to avoid duplicate sleep values
        var workoutTypeData: [String: [(duration: Double, sleepValue: Double)]] = [:]
        
        for session in sessions {
            guard let sleepValue = self.getMetricValue(from: session, for: sleepMetric),
                  let workouts = session.workouts?.allObjects as? [Workout] else { continue }
            
            // Sum durations by workout type for this day
            var dailyWorkoutDurations: [String: Double] = [:]
            for workout in workouts {
                let workoutType = workout.workoutType
                let durationMinutes = workout.durationInMinutes
                dailyWorkoutDurations[workoutType, default: 0] += durationMinutes
            }
            
            // Add one data point per workout type per day (summed duration)
            for (workoutType, totalDuration) in dailyWorkoutDurations {
                if workoutTypeData[workoutType] == nil {
                    workoutTypeData[workoutType] = []
                }
                workoutTypeData[workoutType]?.append((duration: totalDuration, sleepValue: sleepValue))
            }
        }
        
        // Create summary for each workout type that has sufficient data
        var summaries: [CorrelationSummary] = []
        
        for (workoutType, data) in workoutTypeData {
            // Only create summary for workout types with at least 7 data points
            guard data.count >= 7 else {
                print("[CorrelationsViewModel] Skipping \(workoutType) - only \(data.count) data points")
                continue
            }
            
            print("[CorrelationsViewModel] Creating summary for \(workoutType) with \(data.count) data points")
            
            // Convert to the format expected by createBinAnalysis
            let formattedData = data.map { (healthValue: $0.duration, sleepValue: $0.sleepValue) }
            
            // Get appropriate icon for workout type
            let icon = self.iconForWorkoutType(workoutType)
            
            let binResult = await self.createBinAnalysis(
                healthMetricName: workoutType,
                healthMetricIcon: icon,
                sleepMetricName: sleepMetric.displayName,
                data: formattedData,
                unit: "min"
            )
            
            let correlationCoefficient = self.calculateMeanDifference(data: formattedData) // Use mean difference for workout binary data
            let percentageChange = self.computePercentageChange(for: binResult, sleepMetric: sleepMetric, correlationCoefficient: correlationCoefficient)
            let isSignificant = abs(correlationCoefficient) > 5 && binResult.totalSamples >= 7 // Use correlation strength for significance
            
            summaries.append(CorrelationSummary(
                healthMetricName: workoutType,
                healthMetricIcon: binResult.healthMetricIcon,
                sleepMetricName: sleepMetric.displayName,
                sleepMetricIcon: sleepMetric.icon,
                correlationCoefficient: correlationCoefficient,
                percentageChange: percentageChange,
                isSignificant: isSignificant,
                binAnalysisResult: binResult,
                habitImpact: nil
            ))
        }
        
        // Update available workout types for filtering
        await MainActor.run {
            let workoutTypes = Array(workoutTypeData.keys).sorted()
            self.availableWorkoutTypes = workoutTypes
            
            // Auto-select all workout types on first run (similar to habits logic)
            if self.visibleWorkoutTypes.isEmpty && !workoutTypes.isEmpty {
                self.visibleWorkoutTypes = Set(workoutTypes)
                print("[CorrelationsViewModel] Auto-selecting all workout types: \(workoutTypes)")
            }
        }
        
        print("[CorrelationsViewModel] Created \(summaries.count) workout summaries")
        return summaries
    }
    
    // Updated createManuallyTrackedHabitsAnalyses to return summaries
    private func createHabitSummaries(for sleepMetric: CorrelationMetric, sessions: [SleepSessionV2]) async -> [CorrelationSummary] {
        return await viewContext.perform { [weak self] in
            guard let self = self else { return [] }
            
            do {
                // Fetch all manually tracked habit definitions (not archived)
                let habitsFetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                habitsFetchRequest.predicate = NSPredicate(format: "isArchived == NO")
                habitsFetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                let habitDefinitions = try self.viewContext.fetch(habitsFetchRequest)
                
                // Early exit if no manually tracked habits exist
                guard !habitDefinitions.isEmpty else {
                    print("[CorrelationsViewModel] No manually tracked habits found")
                    return []
                }
                
                print("[CorrelationsViewModel] Found \(habitDefinitions.count) manually tracked habits: \(habitDefinitions.map { $0.name }.joined(separator: ", "))")
                
                // Calculate baseline from ALL sleep sessions in the time window (proper comparison baseline)
                let allSleepValues = sessions.compactMap { session in
                    self.getMetricValue(from: session, for: sleepMetric)
                }
                guard !allSleepValues.isEmpty else {
                    print("[CorrelationsViewModel] No sleep data available for baseline calculation")
                    return []
                }
                let overallBaseline = allSleepValues.reduce(0, +) / Double(allSleepValues.count)
                print("[CorrelationsViewModel] Calculated baseline from \(allSleepValues.count) total sleep sessions: \(String(format: "%.1f", overallBaseline))")
                
                // Calculate completion impact for each habit
                var habitSummaries: [CorrelationSummary] = []
                
                for habitDefinition in habitDefinitions {
                    var habitData: [(habitCompleted: Bool, sleepValue: Double)] = []
                    
                    for session in sessions {
                        guard let metricValue = self.getMetricValue(from: session, for: sleepMetric) else { continue }
                        
                        // Look for this specific habit from the session's manualHabits relationship
                        let habitRecordsForSession = session.manualHabits?.allObjects as? [HabitRecord] ?? []
                        let habitCompleted = habitRecordsForSession.contains { record in
                            record.definition == habitDefinition
                        }
                        
                        habitData.append((habitCompleted: habitCompleted, sleepValue: metricValue))
                    }
                    print("[CorrelationsViewModel] Generated \(habitData.count) data points for habit '\(habitDefinition.name)'")
                    
                    // Check minimum data requirements
                    let minDataPoints = 7
                    guard habitData.count >= minDataPoints else {
                        print("[CorrelationsViewModel] Insufficient data for habit '\(habitDefinition.name)': \(habitData.count) < \(minDataPoints)")
                        continue
                    }
                    
                    // Calculate impact: completed days vs not completed days
                    let completedData = habitData.filter { $0.habitCompleted }
                    guard !completedData.isEmpty else { continue } // Only include habits with at least some completion data
                    
                    print("[CorrelationsViewModel] Habit '\(habitDefinition.name)' has \(completedData.count) completed days out of \(habitData.count) total days")
                    
                    let averageCompleted = completedData.map { $0.sleepValue }.reduce(0, +) / Double(completedData.count)
                    
                    // Create a simple BinAnalysisResult for habits
                    let notCompletedData = habitData.filter { !$0.habitCompleted }
                    let averageNotCompleted = notCompletedData.isEmpty ? overallBaseline : 
                        notCompletedData.map { $0.sleepValue }.reduce(0, +) / Double(notCompletedData.count)
                    
                    // Calculate correlation coefficient as mean difference for binary habit data
                    let correlationCoefficient = averageCompleted - (notCompletedData.isEmpty ? overallBaseline : 
                        notCompletedData.map { $0.sleepValue }.reduce(0, +) / Double(notCompletedData.count))
                    
                    // Make percentage change direction-consistent with correlation
                    let rawPercentageChange = ((averageCompleted - overallBaseline) / overallBaseline) * 100
                    let percentageChange = correlationCoefficient >= 0 ? 
                        self.adjustPercentageForGoodDirection(rawPercentageChange, sleepMetric: sleepMetric) :
                        self.adjustPercentageForGoodDirection(-rawPercentageChange, sleepMetric: sleepMetric) // Invert if correlation is negative
                    
                    var isSignificant = abs(correlationCoefficient) > 5 && completedData.count >= 7
                    
                    let habitBins = [
                        HealthMetricBin(
                            range: "Completed",
                            lowerBound: 0.0,
                            upperBound: 1.0,
                            averageSleepMetric: averageCompleted,
                            sampleCount: completedData.count
                        ),
                        HealthMetricBin(
                            range: "Not Completed", 
                            lowerBound: 0.0,
                            upperBound: 1.0,
                            averageSleepMetric: averageNotCompleted,
                            sampleCount: notCompletedData.count
                        )
                    ]
                    
                    let habitBinResult = BinAnalysisResult(
                        healthMetricName: habitDefinition.name,
                        healthMetricIcon: habitDefinition.icon,
                        sleepMetricName: sleepMetric.displayName,
                        bins: habitBins,
                        totalSamples: habitData.count,
                        status: .valid,
                        baseline: overallBaseline
                    )
                    
                    isSignificant = abs(correlationCoefficient) > 5 && completedData.count >= 7
                    
                    habitSummaries.append(CorrelationSummary(
                        healthMetricName: habitDefinition.name,
                        healthMetricIcon: habitDefinition.icon,
                        sleepMetricName: sleepMetric.displayName,
                        sleepMetricIcon: sleepMetric.icon,
                        correlationCoefficient: correlationCoefficient,
                        percentageChange: percentageChange,
                        isSignificant: isSignificant,
                        binAnalysisResult: habitBinResult, // Now includes proper bin analysis
                        habitImpact: averageCompleted
                    ))
                }
                
                // Update available habit names on main actor
                let habitNames = habitSummaries.map { $0.healthMetricName }
                Task { @MainActor in
                    self.availableHabitNames = habitNames
                    // Initialize visible habits to show all by default
                    if self.visibleHabitNames.isEmpty {
                        self.visibleHabitNames = Set(habitNames)
                    }
                }
                
                print("[CorrelationsViewModel] Created \(habitSummaries.count) habit summaries")
                return habitSummaries
                
            } catch {
                print("[CorrelationsViewModel] Error creating habit summaries: \(error)")
                return []
            }
        }
    }
    
    /// Get appropriate SF Symbol icon for workout type
    private func iconForWorkoutType(_ workoutType: String) -> String {
        let lowercased = workoutType.lowercased()
        switch lowercased {
        case let t where t.contains("running") || t.contains("run"):
            return "figure.run"
        case let t where t.contains("walking") || t.contains("walk"):
            return "figure.walk"
        case let t where t.contains("cycling") || t.contains("bike"):
            return "bicycle"
        case let t where t.contains("swimming") || t.contains("swim"):
            return "figure.pool.swim"
        case let t where t.contains("strength") || t.contains("weight"):
            return "dumbbell"
        case let t where t.contains("yoga"):
            return "figure.mind.and.body"
        case let t where t.contains("hiking"):
            return "figure.hiking"
        case let t where t.contains("tennis"):
            return "tennis.racket"
        case let t where t.contains("basketball"):
            return "basketball"
        case let t where t.contains("soccer") || t.contains("football"):
            return "soccerball"
        case let t where t.contains("elliptical"):
            return "figure.elliptical"
        case let t where t.contains("rowing"):
            return "figure.rower"
        default:
            return "figure.strengthtraining.traditional"
        }
    }
    
    // Generate user-friendly impact description based on scaled coefficient
    private func generateImpactDescription(
        coefficient: Double,
        healthMetric: String,
        sleepMetric: CorrelationMetric
    ) -> String {
        let percentageImpact = coefficient * 100

        return "\(String(format: "%.1f", percentageImpact))%"
    }
    
    // Helper function for min-max scaling
    private func minMaxScale(_ data: [Double]) -> [Double] {
        guard let minVal = data.min(), let maxVal = data.max(), minVal != maxVal else {
            return data // Return unchanged if all values are the same
        }
        
        return data.map { ($0 - minVal) / (maxVal - minVal) }
    }
}
