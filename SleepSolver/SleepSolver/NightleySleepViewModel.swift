import Foundation
import CoreData
import Combine
import HealthKit

@MainActor
class NightlySleepViewModel: ObservableObject {
    // MARK: - Data Fetching and Caching
    
    // Dictionary to store fetched sleep sessions (or nil if no data exists) keyed by the sleep day string (e.g., "2025-07-03").
    @Published var sleepSessions: [String: SleepSessionV2?] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentDisplayDate: Date = Calendar.current.startOfDay(for: Date())

    // ADD: Onboarding state properties
    @Published var isOnboardingLoading: Bool = false
    @Published var onboardingProgress: Double = 0.0
    @Published var onboardingStatusMessage: String? = nil

    private let calendar = Calendar.current
    // Note: fetchingDays removed - individual date fetching tracking no longer needed
    
    // MARK: - Chart Performance Optimization
    // Consolidated chart coordination mechanism
    private var pendingChartFetches: [String: Task<Void, Error>] = [:]
    private var activeRangeFetches: Set<String> = []
    private let chartFetchDebounceInterval: TimeInterval = 0.5
    
    // Cache management for performance
    private var lastPrefetchDate: Date?
    private let prefetchInterval: TimeInterval = 3600 // 1 hour between prefetches
    
    // Public helper to check if data is currently being fetched for a date
    // Note: Always returns false since individual date fetching is now done via direct CoreData lookups
    func isFetching(for date: Date) -> Bool {
        return false // Individual date fetching removed - using direct CoreData lookups
    }
    private let viewContext: NSManagedObjectContext
    private let healthKitManager: HealthKitManager
    private var cancellables = Set<AnyCancellable>()

    init(context: NSManagedObjectContext, healthKitManager: HealthKitManager = .shared) {
        self.viewContext = context
        self.healthKitManager = healthKitManager
        print("[VM] 📱 ViewModel initialized - sync handled by coordinator")
        print("[VM] 📱 Context: \(context)")
        
        // Listen for sync completion to refresh cache
        NotificationCenter.default.addObserver(
            forName: .shouldRefreshSleepCache, 
            object: nil, 
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.rebuildPersistentCacheIfNeeded()
            }
        }
        
        restoreCacheFromMapping()
        Task {
            await self.rebuildPersistentCacheIfNeeded()
        }
        // Removed: Prefetch common chart ranges after initial load
    }

    // Note: Individual date fetching removed - now using direct CoreData lookups in sleepSession(for:)
    // This method is kept for compatibility but is essentially a no-op for individual sleep summary lookups
    // fetchDataIfNotPresent removed.

    // ADD: Function for fetching historical data during onboarding
    // The progressUpdate callback now provides: progress (Double?), status (String?), error (Error?)
    func fetchHistoricalData(months: Int, progressUpdate: @escaping (Double?, String?, Error?) -> Void) {
        self.isOnboardingLoading = true
        self.onboardingProgress = 0.0
        self.onboardingStatusMessage = "Starting historical data sync..."
        progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, nil)

        Task(priority: .userInitiated) {
            var accumulatedError: Error? = nil
            let targetContext = PersistenceController.shared.container.viewContext // Or a background context if preferred for HKM

            // --- Step 1: Fetch and Save historical sleep data using NewSleepDataManager ---
            self.onboardingStatusMessage = "Fetching historical sleep records from HealthKit..."
            progressUpdate(0.05, self.onboardingStatusMessage, nil) // Initial small progress
            
            let newSleepManagerFetchSuccessful = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                NewSleepDataManager.shared.fetchNewSleepDataWithAnchoredQuery(context: targetContext, fetchAll: true) { error in
                    DispatchQueue.main.async {
                        // Update progress to 50% when sleep fetch completes
                        self.onboardingProgress = 0.5
                        self.onboardingStatusMessage = "Historical sleep data fetch complete."
                        progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, nil)
                    }
                    
                    if let error = error {
                        accumulatedError = error
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(returning: true)
                    }
                }
            }

            if Task.isCancelled {
                self.isOnboardingLoading = false
                self.onboardingStatusMessage = "Onboarding cancelled during HealthKit sync."
                progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, NSError(domain: "ViewModel", code: 99, userInfo: [NSLocalizedDescriptionKey: "Onboarding cancelled by user."]))
                return
            }

            if !newSleepManagerFetchSuccessful {
                self.isOnboardingLoading = false
                self.onboardingStatusMessage = "Failed to fetch historical sleep data from HealthKit."
                progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, accumulatedError)
                return // Stop if NewSleepDataManager historical fetch failed
            }
            
            // --- Step 2: Fetch and Save historical habit metrics data using HealthKitManager ---
            self.onboardingProgress = 0.5 // Sleep data complete, now habits
            self.onboardingStatusMessage = "Fetching historical habit metrics from HealthKit..."
            progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, nil)
            
            // Fix: Use end of today to ensure today's data is included in the range
            let endDate = calendar.dateInterval(of: .day, for: Date())?.end ?? Date()
            guard let habitStartDate = calendar.date(byAdding: .month, value: -months, to: endDate) else {
                let error = NSError(domain: "ViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not calculate start date for habit metrics sync."])
                self.isOnboardingLoading = false
                self.onboardingStatusMessage = "Error calculating dates for habit metrics sync."
                progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, error)
                return
            }
            
            // Sync historical habit metrics using the existing method
            print("[NightlySleepViewModel] Starting historical habit metrics sync from \(habitStartDate) to \(endDate)")
            await healthKitManager.syncHealthMetricsForDateRange(habitStartDate, endDate, context: targetContext)
            print("[NightlySleepViewModel] Completed historical habit metrics sync")
            
            // --- Step 3: Load the fetched historical sleep data from Core Data into the ViewModel ---
            self.onboardingProgress = 0.7 // Habit metrics complete, now loading
            self.onboardingStatusMessage = "Loading fetched sleep data into app..."
            progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, nil)

            guard let startDate = calendar.date(byAdding: .month, value: -months, to: endDate) else { return }

            // Calculate total days to load - now properly includes today since endDate is end of day
            let totalDaysToLoad = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0

            // Debug logging to verify date range includes today
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("[DEBUG] Onboarding date range:")
            print("[DEBUG] startDate: \(formatter.string(from: startDate))")
            print("[DEBUG] endDate: \(formatter.string(from: endDate))")
            print("[DEBUG] totalDaysToLoad: \(totalDaysToLoad)")
            print("[DEBUG] Today should be included: \(calendar.isDate(Date(), inSameDayAs: endDate) || endDate > Date())")

            if totalDaysToLoad > 0 {
                var daysLoaded = 0
                for i in 0..<totalDaysToLoad {
                    let day = calendar.date(byAdding: .day, value: i, to: startDate)!
                    let startOfDay = calendar.startOfDay(for: day)
                    // Use the new 6pm-6pm window logic and SleepSessionV2
                    let session = self.sleepSession(for: startOfDay)
                    await MainActor.run {
                        let key = self.cacheKey(for: startOfDay)
                        self.sleepSessions[key] = session
                    }
                    daysLoaded += 1
                    // This loading part takes the remaining 50% of progress
                    self.onboardingProgress = 0.5 + (Double(daysLoaded) / Double(totalDaysToLoad)) * 0.5
                    progressUpdate(self.onboardingProgress, nil, nil) // Update progress, status is per-month
                }
            } else {
                self.onboardingProgress = 1.0 // No days to load, mark as complete
                progressUpdate(self.onboardingProgress, "No past sleep data to load from local store.", nil)
            }

            if Task.isCancelled {
                self.isOnboardingLoading = false
                self.onboardingStatusMessage = "Onboarding cancelled during data loading."
                progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, NSError(domain: "ViewModel", code: 99, userInfo: [NSLocalizedDescriptionKey: "Onboarding cancelled by user."]))
                return
            }

            // --- Final Update ---
            self.isOnboardingLoading = false
            self.onboardingStatusMessage = "Historical sync complete!"
            self.onboardingProgress = 1.0 // Ensure it reaches 100%
            progressUpdate(self.onboardingProgress, self.onboardingStatusMessage, nil)
        } // End Task
    }

    // Helper async wrapper for habit data fetching (REMOVED)
    // private func fetchAndStoreHistoricalHabitDataAsync(...) { ... }


    // Function to check authorization status (can be called from Onboarding or main view)
    func checkAuthorization(completion: @escaping (Bool) -> Void) {
        healthKitManager.checkAuthorizationStatus { authorized in
            completion(authorized)
        }
    }

    // Function to request authorization (can be called from Onboarding or main view)
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        healthKitManager.requestAuthorization {
            success, error in
            completion(success, error)
        }
    }

    // Helper to get sleep session for a specific date - Uses SleepSessionV2 with timezone-agnostic 6pm-6pm logic
    func sleepSession(for date: Date) -> SleepSessionV2? {
        print("[VM] 🔍 sleepSession(for:) called for date: \(date)")
        
        // Calculate the 6pm-to-6pm window in the user's current timezone.
        let window = calculate6pmTo6pmWindow(for: date)
        print("[VM] 🔍 6pm window: \(window.start) to \(window.end)")
        
        // The predicate now correctly finds a SleepSessionV2 where the UTC-based
        // ownershipDay falls within the user's local 6pm-to-6pm time window.
        // Return any session, even if not finalized (UI will handle the finalization state)
        let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay < %@", 
                                           window.start as CVarArg, 
                                           window.end as CVarArg)
        
        // Sort by the actual start time to get the most relevant session if multiple fall in the window.
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "startDateUTC", ascending: false)]
        fetchRequest.fetchLimit = 1
        
        do {
            let session = try viewContext.fetch(fetchRequest).first
            if let session = session {
                print("[VM] 🔍 Found session:")
                print("[VM]   - ObjectID: \(session.objectID)")
                print("[VM]   - isFinalized: \(session.isFinalized)")
                print("[VM]   - sleepScore: \(session.sleepScore)")
                print("[VM]   - ownershipDay: \(session.ownershipDay)")
            } else {
                print("[VM] 🔍 No session found for date: \(date)")
            }
            return session
        } catch {
            print("[VM] ❌ Error in SleepSessionV2 fetch for date \(date): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Calculate the 6pm-6pm window for a given display date in the user's current timezone.
    /// - Parameter displayDate: The date for which to calculate the window.
    /// - Returns: A DateRange representing 6pm previous day to 6pm display day.
    private func calculate6pmTo6pmWindow(for displayDate: Date) -> DateRange {
        let calendar = Calendar.current // Uses the user's current timezone
        let startOfDay = calendar.startOfDay(for: displayDate)
        
        // Get 6pm on the display date.
        let endOfWindow = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startOfDay) ?? startOfDay
        
        // Get 6pm on the previous day (which is 24 hours before the end of the window).
        let startOfWindow = calendar.date(byAdding: .hour, value: -24, to: endOfWindow) ?? endOfWindow
        
        return DateRange(start: startOfWindow, end: endOfWindow)
    }

    // Function to update the currently displayed date
    func changeDisplayDate(to date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        currentDisplayDate = startOfDay
        
        // Note: Individual date caching removed - sleepSession(for:) now uses directCoreData lookups
        // Data will be fetched on-demand when sleepSession(for:) is called
        // Removed fetchWeekBatch to eliminate redundant individual date fetching
    }

    // Note: fetchWeekBatch removed - individual date caching no longer needed
    // Chart prefetching is handled by prefetchCommonChartRanges() and chart bulk loading
    // Individual sleep summary lookups use direct CoreData fetches via sleepSession(for:)

    // MARK: - Post-Onboarding Sync
    func triggerPostOnboardingSyncAndRefresh() {
        let today = calendar.startOfDay(for: Date())
        let key = cacheKey(for: today)
        sleepSessions[key] = nil
        print("[VM] 📱 Refresh data - individual lookups will fetch fresh data on demand")
        Task {
            await self.rebuildPersistentCacheIfNeeded()
        }
    }

    // MARK: - Persistent Cache Metadata Keys
    private let cacheLastUpdatedKey = "nightlySleepCache_lastUpdated"
    private let cacheTimezoneKey = "nightlySleepCache_timezone"

    // MARK: - Persistent Cache Mapping Keys
    private let cacheMappingKey = "nightlySleepCache_mapping"

    // MARK: - Timezone/Cache Metadata Helpers
    private func currentTimezoneIdentifier() -> String {
        TimeZone.current.identifier
    }

    private func persistCacheMetadata() {
        UserDefaults.standard.set(Date(), forKey: cacheLastUpdatedKey)
        UserDefaults.standard.set(currentTimezoneIdentifier(), forKey: cacheTimezoneKey)
    }

    private func loadCacheMetadata() -> (lastUpdated: Date?, timezone: String?) {
        let lastUpdated = UserDefaults.standard.object(forKey: cacheLastUpdatedKey) as? Date
        let timezone = UserDefaults.standard.string(forKey: cacheTimezoneKey)
        return (lastUpdated, timezone)
    }

    private func hasTimezoneChanged() -> Bool {
        let storedTimezone = UserDefaults.standard.string(forKey: cacheTimezoneKey)
        return storedTimezone != currentTimezoneIdentifier()
    }

    // MARK: - Persistent 180-Day Cache (with Timezone/Metadata logic)
    /// Ensures the cache always contains the last 180 days of sessions for instant chart switching.
    func rebuildPersistentCache() async {
        let startTime = Date() // Start timer
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -179, to: today) else { return }

        await loadBulkSleepData(from: startDate, to: today)
        manageCacheSize(maxCacheAge: 180)
        persistCacheMapping()

        let duration = Date().timeIntervalSince(startTime)
        print(String(format: "[VM] ⏱️ Persistent cache rebuilt and mapped in %.3f seconds.", duration))
    }

    /// Keeps only the last `maxCacheAge` days in cache (default 200, but 180 for persistent cache)
    private func manageCacheSize(maxCacheAge: Int = 200) {
        let today = calendar.startOfDay(for: Date())
        guard let cutoffDate = calendar.date(byAdding: .day, value: -maxCacheAge, to: today) else { return }
        let oldKeys = sleepSessions.keys.filter { key in
            if let keyDate = ISO8601DateFormatter().date(from: key) {
                return keyDate < cutoffDate
            }
            return false
        }
        for key in oldKeys { sleepSessions.removeValue(forKey: key) }
    }

    // MARK: - Data Retrieval for Onboarding
    func fetchAllTimeInBedData() -> [Double] {
        var timeInBedData: [Double] = []
        let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        // For onboarding calculations, we can use all sessions (finalized or not)
        // since we just need the time in bed data

        viewContext.performAndWait { // Synchronous fetch for simplicity here
            do {
                let sessions = try viewContext.fetch(fetchRequest)
                timeInBedData = sessions.map { $0.totalTimeInBed / 3600.0 } // Convert seconds to hours
                print("[VM] Fetched \(timeInBedData.count) totalTimeInBed samples from CoreData for onboarding calculation.")
            } catch {
                print("[VM] Error fetching all SleepSessionV2 data from CoreData: \(error.localizedDescription)")
                // Return empty array on error
            }
        }
        return timeInBedData
    }

    // MARK: - Correlation-Specific Data Loading
    
    // loadDataForCorrelations has been removed as it depends on the deprecated SleepSession model.
    // The CorrelationsView will be updated separately to use SleepSessionV2.

    // MARK: - Bulk Data Loading
    // Legacy method removed: loadDataForDateRange
    // All bulk loading now uses loadBulkSleepData (SleepSessionV2, 6pm-6pm window)
    private var bulkLoadInProgress: Set<String> = [] // Deduplication for bulk loads
    private func loadBulkSleepData(from startDate: Date, to endDate: Date) async {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let rangeDescription = "\(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
        let rangeKey = "\(startDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)"

        if bulkLoadInProgress.contains(rangeKey) {
            print("[VM] Skipping bulk load for range \(rangeDescription) (already in progress)")
            return
        }

        bulkLoadInProgress.insert(rangeKey)
        defer { bulkLoadInProgress.remove(rangeKey) }

        let calendar = Calendar.current
        var newCache: [String: SleepSessionV2?] = [:]

        // 1. Define the entire date range for the fetch.
        // The window for a sleep day (e.g., July 5) is 6pm July 4 to 6pm July 5.
        // So, the full fetch window starts at 6pm on the day *before* the startDate.
        guard let windowStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: startDate)!),
              let windowEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: endDate) else {
            print("[VM] ❌ Error: Could not calculate the date window for bulk fetch.")
            return
        }

        // 2. Perform a single fetch for the entire range.
        let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay < %@", windowStart as CVarArg, windowEnd as CVarArg)
        
        var allSessionsInRange: [SleepSessionV2] = []
        do {
            allSessionsInRange = try viewContext.fetch(fetchRequest)
        } catch {
            print("[VM] ❌ Error fetching all SleepSessionV2 for range \(rangeDescription): \(error)")
            return // Exit if the fetch fails
        }

        // 3. Process the results in memory.
        // Group sessions by their ownership day to handle duplicates, keeping the one that started latest.
        var sessionsByDay: [Date: SleepSessionV2] = [:]
        for session in allSessionsInRange {
            let ownershipDay = session.ownershipDay
            let startOfDay = calendar.startOfDay(for: ownershipDay)

            if let existingSession = sessionsByDay[startOfDay] {
                // If a session for this day already exists, keep the one with the longer duration.
                let newStartDate = session.startDateUTC
                let newEndDate = session.endDateUTC
                let existingStartDate = existingSession.startDateUTC
                let existingEndDate = existingSession.endDateUTC

                let newDuration = newEndDate.timeIntervalSince(newStartDate)
                let existingDuration = existingEndDate.timeIntervalSince(existingStartDate)

                if newDuration > existingDuration {
                    sessionsByDay[startOfDay] = session
                }
            } else {
                sessionsByDay[startOfDay] = session
            }
        }

        // 4. Populate the new cache with the processed sessions.
        var currentDate = startDate
        while currentDate <= endDate {
            let startOfDay = calendar.startOfDay(for: currentDate)
            let key = cacheKey(for: startOfDay)
            // Assign the session from our processed dictionary, or nil if none existed for that day.
            newCache[key] = sessionsByDay[startOfDay]
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // 5. Update the main @Published property on the main thread.
        await MainActor.run {
            self.sleepSessions = newCache
            print("[VM] ✅ Bulk loaded and processed \(sessionsByDay.count) unique sleep sessions for range \(rangeDescription)")
            manageCacheSize() // Ensure cache stays within limits after bulk load
        }
    }
    
    // MARK: - Phase 1: Smart Tap-to-Refresh Methods
    
    /// Performs incremental HealthKit sync for a specific date range
    /// Used by tap-to-refresh to sync only necessary data
    func performIncrementalSync(from startDate: Date, to endDate: Date) {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        
        print("[VM] Performing incremental sync from \(normalizedStart) to \(normalizedEnd)")
        
        // Background sync to avoid blocking UI - REMOVED, now handled by SleepDataSyncCoordinator
        // Just load from CoreData
        print("[VM] 📖 Loading range from CoreData only: \(normalizedStart) to \(normalizedEnd)")
    }
    
    /// Refreshes cached data for the selected date and surrounding days
    /// Updates UI data without triggering expensive HealthKit syncs
    func refreshCachedData(for selectedDate: Date) {
        let startOfDay = calendar.startOfDay(for: selectedDate)
        
        print("[VM] Refreshing cached data for \(startOfDay)")
        
        // FIXED: Instead of clearing cache, immediately reload fresh data for common chart ranges
        // This ensures charts always have data to render after refresh
        Task {
            await self.rebuildPersistentCacheIfNeeded()
        }
        
        // Note: Individual date lookups will fetch fresh data on demand via sleepSession(for:)
        // No need to proactively fetch - data will be loaded when UI requests it
    }
    
    /// Comprehensive cache refresh for force sync scenarios
    /// Clears cache for all common chart time ranges to prevent stale data issues
    func refreshCachedDataForForceSync() {
        let today = calendar.startOfDay(for: Date())
        let rangesToClear = [ ("week", 7), ("month", 30), ("sixMonths", 180) ]
        for (_, days) in rangesToClear {
            for dayOffset in 0..<days {
                if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                    let key = cacheKey(for: date)
                    sleepSessions[key] = nil
                }
            }
        }
        print("[VM] Force sync cache refresh complete - all chart ranges cleared")
        Task {
            await self.rebuildPersistentCacheIfNeeded()
        }
    }
    
    // Note: syncSleepDataForRange removed - sync now handled by SleepDataSyncCoordinator

    /// Checks if the persistent cache needs to be rebuilt (empty, timezone changed, or stale) and triggers a rebuild if needed.
    func rebuildPersistentCacheIfNeeded() async {
        let (lastUpdated, storedTimezone) = loadCacheMetadata()
        let cacheIsEmpty = sleepSessions.isEmpty
        let timezoneChanged = storedTimezone != nil && storedTimezone != currentTimezoneIdentifier()
        let today = calendar.startOfDay(for: Date())
        let cacheIsStale: Bool = {
            guard let last = lastUpdated else { return true }
            let lastDay = calendar.startOfDay(for: last)
            return lastDay != today
        }()
        let reason: String
        if cacheIsEmpty {
            reason = "empty"
        } else if timezoneChanged {
            reason = "timezone changed"
        } else {
            reason = "stale"
        }
        if cacheIsEmpty || timezoneChanged || cacheIsStale {
            print("[VM] Rebuilding persistent cache (reason: \(reason))")
            await rebuildPersistentCache()
            persistCacheMetadata()
        } else {
            print("[VM] Persistent cache is valid (no rebuild needed)")
        }
    }

    // Helper: Convert Date to string for mapping (ISO8601)
    private func cacheDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// Public helper to get the cache key for a given date (6pm–6pm logic, ISO8601 string)
    public func cacheKey(for date: Date) -> String {
        let calendar = Calendar.current
        // The cache is built using startOfDay, so use that for the key
        let startOfDay = calendar.startOfDay(for: date)
        return cacheDateString(startOfDay)
    }

    // Helper: Save cache mapping to UserDefaults
    private func persistCacheMapping() {
        let mapping: [String: String] = sleepSessions.reduce(into: [String: String]()) { dict, pair in
            let (key, session) = pair
            if let objectID = session?.objectID.uriRepresentation().absoluteString {
                dict[key] = objectID
            }
        }
        UserDefaults.standard.set(mapping, forKey: cacheMappingKey)
    }

    // Helper: Load cache mapping from UserDefaults and restore in-memory cache
    private func restoreCacheFromMapping() {
        guard let mapping = UserDefaults.standard.dictionary(forKey: cacheMappingKey) as? [String: String] else {
            // No mapping found is a normal case on first launch, so no print needed.
            return
        }

        var restored: [String: SleepSessionV2?] = [:]
        for (key, uriString) in mapping {
            if let uri = URL(string: uriString),
               let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri) {
                do {
                    // Faulting the object without fetching its properties is very fast.
                    let obj = try viewContext.existingObject(with: objectID) as? SleepSessionV2
                    restored[key] = obj
                } catch {
                    // This might happen if an object was deleted but the mapping wasn't updated.
                    // Silently fail and just don't add it to the cache.
                    restored[key] = nil
                }
            }
        }
        sleepSessions = restored
    }

    // --- Update cache after bulk load or refresh ---
    // (If you have other methods that update sleepSessions, call persistCacheMapping() after those updates.)
    

    
    // MARK: - Reactive UI Updates
    
    /// Force refresh of UI for the current date
    /// This can be called when we know a session has been updated
    @Published var uiRefreshTrigger: UUID = UUID()
    
    func refreshUI() {
        let oldTrigger = uiRefreshTrigger
        uiRefreshTrigger = UUID()
        print("[VM] 🔄 UI refresh triggered: \(oldTrigger) -> \(uiRefreshTrigger)")
    }
    
    // MARK: - Manual UI Refresh Methods
    
    /// Call this method when you know a session has been finalized and you want to immediately refresh the UI
    func triggerUIRefreshForDate(_ date: Date) {
        Task { @MainActor in
            // Clear cache for this date to force fresh fetch
            let key = cacheKey(for: date)
            sleepSessions[key] = nil
            
            // Trigger UI refresh
            refreshUI()
            
            print("[VM] ✅ Manual UI refresh triggered for date: \(date)")
        }
    }
}
