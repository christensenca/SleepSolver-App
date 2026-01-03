import Foundation
import CoreData
import HealthKit

extension Notification.Name {
    static let sleepDataSyncDidComplete = Notification.Name("sleepDataSyncDidComplete")
    static let shouldRefreshSleepCache = Notification.Name("shouldRefreshSleepCache")
}

/// Phase 2: Centralized sync coordinator to eliminate redundant HealthKit sync patterns
/// Replaces multiple overlapping sync triggers with intelligent, coordinated syncing
/// Handles sleep data synchronization (habit data now handled automatically by SleepAnalysisEngine)
@MainActor
class SleepDataSyncCoordinator: ObservableObject {
    
    // MARK: - Singleton
    static let shared = SleepDataSyncCoordinator()
    
    // MARK: - Dependencies
    private let healthKitManager: HealthKitManager
    private let viewContext: NSManagedObjectContext
    private let calendar = Calendar.current
    
    // MARK: - State Management
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date?  // For complete sleep sync
    @Published var syncProgress: Double = 0.0
    @Published var syncStatus: String?
    
    // MARK: - Data Availability Tracking
    enum DataAvailability {
        case unknown        // Not yet checked
        case available      // Data exists in CoreData
        case missing        // Confirmed no data exists (prevent retry loops)
        case syncing        // Currently being fetched
    }
    
    // Track data availability to prevent unnecessary sync attempts
    private var dataAvailability: [Date: DataAvailability] = [:]
    
    // MARK: - Sync Coordination
    private var activeSyncTasks: Set<String> = []
    private var pendingSyncRanges: [DateRange] = []
    private let syncQueue = DispatchQueue(label: "com.sleepsolver.synccoordinator", qos: .userInitiated)
    
    // MARK: - Concurrency Control
    private var ongoingSyncOperations: Set<String> = []
    private let concurrencyLock = NSLock()
    
    // MARK: - Configuration
    private let minimumSyncInterval: TimeInterval = 300 // 5 minutes between full syncs
    private let retryBackoffInterval: TimeInterval = 60 // 1 minute before retrying failed syncs
    private let maxRetryAttempts = 3
    
    // MARK: - Initialization
    private init(
        healthKitManager: HealthKitManager = .shared,
        viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.healthKitManager = healthKitManager
        self.viewContext = viewContext
        
        // Initialize last sync time from UserDefaults
        if let lastSync = UserDefaults.standard.object(forKey: "lastHealthKitSync") as? Date {
            self.lastSyncTime = lastSync
        }
    }
    
    // MARK: - Public Sync Interface
    
    /// Primary smart sync method - uses anchor-based incremental sync
    func requestSmartSync(priority: SyncPriority = .userInitiated) async {
        let syncId = "smart_sync_\(Date().timeIntervalSince1970)"
        
        print("[SyncCoordinator] 🧠 Smart sync requested - using anchor-based incremental sync")
        
        // Check if sync is needed
        guard shouldPerformSync(priority: priority) else {
            print("[SyncCoordinator] ⏸️ Skipping sync - not needed")
            return
        }
        
        await performSync(id: syncId, priority: priority)
    }
    
    /// App launch sync - background smart sync
    func requestAppLaunchSync() async {
        print("[SyncCoordinator] 🚀 App launch sync requested")
        await requestSmartSync(priority: .background)
    }
    
    /// Onboarding sync - performs a full sync pipeline with 3-month limited data fetch
    func requestOnboardingSync() async {
        let syncId = "onboarding_sync_\(Date().timeIntervalSince1970)"
        
        print("[SyncCoordinator] 🚀 Onboarding sync requested (last 3 months with full processing)")
        
        await performOnboardingSync(id: syncId)
    }
    
    // MARK: - Core Sync & Data Handling

    private func performOnboardingSync(id: String) async {
        // Prevent duplicate syncs
        guard !activeSyncTasks.contains(id) else { 
            print("[SyncCoordinator] ⚠️ Onboarding sync \(id) already active - skipping duplicate")
            return 
        }
        
        activeSyncTasks.insert(id)
        defer { activeSyncTasks.remove(id) }
        
        print("[SyncCoordinator] 🔄 Starting onboarding sync \(id) with full processing pipeline")
        
        // Update UI state
        await MainActor.run {
            isSyncing = true
            syncStatus = "Starting 3-month historical data sync..."
            syncProgress = 0.0
        }
        
        // Step 1: Fetch 3-month limited sleep data using onboarding method
        print("[SyncCoordinator] 😴 Fetching 3-month sleep data for onboarding...")
        await MainActor.run { syncProgress = 0.1 }
        
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        let sleepSyncSuccess = await withCheckedContinuation { continuation in
            NewSleepDataManager.shared.fetchOnboardingSleepData(context: backgroundContext) { error in
                if let error = error {
                    print("[SyncCoordinator] ❌ Onboarding sleep data fetch failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    print("[SyncCoordinator] ✅ Onboarding sleep data fetch completed successfully")
                    continuation.resume(returning: true)
                }
            }
        }
        
        guard sleepSyncSuccess else {
            await MainActor.run {
                isSyncing = false
                syncStatus = "Onboarding sync failed. Please try again."
                syncProgress = 0.0
            }
            return
        }
        
        await MainActor.run { syncProgress = 0.4 }
        
        // Step 2: Sync wrist temperature data
        print("[SyncCoordinator] 🌡️ Syncing wrist temperature data...")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            HealthMetricsManager.shared.fetchNewWristTemperatureData(context: viewContext) { error in
                if let error = error {
                    print("[SyncCoordinator] ❌ Wrist temperature sync error: \(error.localizedDescription)")
                } else {
                    print("[SyncCoordinator] ✅ Wrist temperature sync completed successfully")
                }
                continuation.resume()
            }
        }

        await MainActor.run { syncProgress = 0.6 }
        
        // Step 3: Resolve periods into sessions using SleepAnalysisIntegration
        print("[SyncCoordinator] 🔄 Processing sleep periods into sessions...")
        let sleepAnalysis = SleepAnalysisIntegration(context: viewContext)
        await sleepAnalysis.performIncrementalSleepAnalysis()
        print("[SyncCoordinator] ✅ Sleep analysis integration completed successfully")

        await MainActor.run { syncProgress = 0.8 }

        // Step 4: Run recovery analysis after all data is synced and processed
        print("[SyncCoordinator] 🧠 Calculating recovery metrics for all eligible sessions...")
        let analysisEngine = SleepAnalysisEngine(context: viewContext)
        await analysisEngine.runRecoveryAnalysisForAllEligibleSessions()
        print("[SyncCoordinator] ✅ Recovery metrics calculation completed.")

        // Update last sync time and save to UserDefaults
        let syncTime = Date()
        await MainActor.run {
            lastSyncTime = syncTime
            UserDefaults.standard.set(syncTime, forKey: "lastHealthKitSync")
            syncProgress = 1.0
            syncStatus = "Onboarding sync complete."
        }
        
        print("[SyncCoordinator] ✅ Completed onboarding sync \(id) at \(syncTime)")
        
        await MainActor.run {
            isSyncing = false
            syncStatus = nil
            syncProgress = 0.0
        }
        
        // After all processing is done, post notifications
        NotificationCenter.default.post(name: .sleepDataSyncDidComplete, object: nil)
        NotificationCenter.default.post(name: .shouldRefreshSleepCache, object: nil)
        print("[SyncDataSyncCoordinator] Onboarding sync process completed and notifications posted.")
    }
    
    // MARK: - Core Sync Logic
    
    private func performSync(
        id: String,
        priority: SyncPriority
    ) async {
        // Prevent duplicate syncs
        guard !activeSyncTasks.contains(id) else { 
            print("[SyncCoordinator] ⚠️ Sync \(id) already active - skipping duplicate")
            return 
        }
        
        activeSyncTasks.insert(id)
        defer { activeSyncTasks.remove(id) }
        
        print("[SyncCoordinator] 🔄 Starting sync \(id)")
        
        // Update UI state
        await MainActor.run {
            isSyncing = true
            syncStatus = "Syncing data..."
            syncProgress = 0.0
        }
        
        // Note: Habit data is now automatically fetched by SleepAnalysisEngine when creating SleepSessionV2
        
        await MainActor.run { syncProgress = 0.4 }
        
        // Use NewSleepDataManager anchor query for SleepSessionV2 sync
        print("[SyncCoordinator] 😴 Syncing SleepSessionV2 data using NewSleepDataManager...")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NewSleepDataManager.shared.fetchNewSleepDataWithAnchoredQuery(context: viewContext) { error in
                if let error = error {
                    print("[SyncCoordinator] ❌ NewSleepDataManager sync error: \(error.localizedDescription)")
                } else {
                    print("[SyncCoordinator] ✅ NewSleepDataManager sync completed successfully")
                }
                continuation.resume()
            }
        }

        await MainActor.run { syncProgress = 0.6 }
        
        // Sync wrist temperature data
        print("[SyncCoordinator] 🌡️ Syncing wrist temperature data...")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            HealthMetricsManager.shared.fetchNewWristTemperatureData(context: viewContext) { error in
                if let error = error {
                    print("[SyncCoordinator] ❌ Wrist temperature sync error: \(error.localizedDescription)")
                } else {
                    print("[SyncCoordinator] ✅ Wrist temperature sync completed successfully")
                }
                continuation.resume()
            }
        }

        await MainActor.run { syncProgress = 0.8 }
        
        // Resolve periods into sessions using SleepAnalysisIntegration
        print("[SyncCoordinator] 🔄 Processing sleep periods into sessions...")
        let sleepAnalysis = SleepAnalysisIntegration(context: viewContext)
        await sleepAnalysis.performIncrementalSleepAnalysis()
        print("[SyncCoordinator] ✅ Sleep analysis integration completed successfully")

        await MainActor.run { syncProgress = 0.9 }

        // **NEW STEP**: Run recovery analysis after all data is synced and processed
        print("[SyncCoordinator] 🧠 Calculating recovery metrics for all eligible sessions at \(Date())...")
        let analysisEngine = SleepAnalysisEngine(context: viewContext)
        await analysisEngine.runRecoveryAnalysisForAllEligibleSessions()
        print("[SyncCoordinator] ✅ Recovery metrics calculation completed.")

        // Update last sync time and save to UserDefaults
        let syncTime = Date()
        await MainActor.run {
            lastSyncTime = syncTime
            UserDefaults.standard.set(syncTime, forKey: "lastHealthKitSync")
            syncProgress = 1.0
        }
        
        print("[SyncCoordinator] ✅ Completed sync \(id) at \(syncTime)")
        
        await MainActor.run {
            isSyncing = false
            syncStatus = nil
            syncProgress = 0.0
        }
        
        // After all processing is done, post notifications
        NotificationCenter.default.post(name: .sleepDataSyncDidComplete, object: nil)
        NotificationCenter.default.post(name: .shouldRefreshSleepCache, object: nil)
        print("[SleepDataSyncCoordinator] Full sync process completed and notifications posted.")
    }
    
    // MARK: - Sync Decision Logic
    
    /// Check if sync should be performed based on priority and timing
    private func shouldPerformSync(priority: SyncPriority) -> Bool {
        // Always allow user-initiated syncs (refresh button)
        if priority == .userInitiated {
            print("[SyncCoordinator] ✅ User-initiated sync - proceeding")
            return true
        }
        
        // For background syncs (app launch), check minimum interval
        if let lastSync = lastSyncTime {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            let minimumInterval: TimeInterval = 300 // 5 minutes
            
            if timeSinceLastSync < minimumInterval {
                print("[SyncCoordinator] ⏸️ Background sync too recent (\(Int(timeSinceLastSync))s < \(Int(minimumInterval))s)")
                return false
            }
        }
        
        print("[SyncCoordinator] ✅ Background sync approved")
        return true
    }
    
    // MARK: - Sync Decision Logic
    
    private func shouldSync(for dateRange: DateRange, priority: SyncPriority) -> Bool {
        // Deprecated - use shouldPerformSync instead
        return shouldPerformSync(priority: priority)
    }
    
    private func hasMissingData(in dateRange: DateRange) -> Bool {
        var currentDate = dateRange.start
        while currentDate <= dateRange.end {
            let availability = dataAvailability[currentDate] ?? .unknown
            if availability == .unknown || availability == .missing {
                return true
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        return false
    }
    
    // MARK: - Data Management (Removed old sync methods)
    
    private func updateDataAvailability(for dateRange: DateRange) async throws {
        // TODO: MIGRATION - Update to check SleepSessionV2 instead of legacy SleepSession
        // Check CoreData for actual data availability
        let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "startDateUTC >= %@ AND startDateUTC <= %@", 
                                           dateRange.start as CVarArg, 
                                           dateRange.end as CVarArg)
        
        do {
            let sessions = try await viewContext.perform {
                try self.viewContext.fetch(fetchRequest)
            }
            
            // Update availability cache
            await MainActor.run {
                let sessionsByDate = Dictionary(grouping: sessions) { session in
                    self.calendar.startOfDay(for: session.ownershipDay)
                }
                
                var currentDate = dateRange.start
                while currentDate <= dateRange.end {
                    if sessionsByDate[currentDate] != nil {
                        dataAvailability[currentDate] = .available
                    } else {
                        dataAvailability[currentDate] = .missing
                    }
                    
                    guard let nextDate = self.calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                    currentDate = nextDate
                }
            }
        } catch {
            print("[SyncCoordinator] Error updating data availability: \(error)")
        }
    }
    
    private func clearDataAvailability(for dateRange: DateRange) {
        var currentDate = dateRange.start
        while currentDate <= dateRange.end {
            dataAvailability.removeValue(forKey: currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
    }
    
    // MARK: - Utility Methods
    
    private func formatDateRange(_ dateRange: DateRange) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        
        if calendar.isDate(dateRange.start, inSameDayAs: dateRange.end) {
            return formatter.string(from: dateRange.start)
        } else {
            return "\(formatter.string(from: dateRange.start)) - \(formatter.string(from: dateRange.end))"
        }
    }
    
    // MARK: - Public Query Methods
    
    /// Check if data is available for a specific date
    func isDataAvailable(for date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        return dataAvailability[startOfDay] == .available
    }
    
    /// Check if data is currently being synced
    func isDataSyncing(for date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        return dataAvailability[startOfDay] == .syncing
    }
    
    /// Fetch SleepSessionV2 for a specific display date using timezone-agnostic 6pm-6pm logic
    /// This is the primary method for UI components to get sleep data for display
    /// - Parameter displayDate: The date to show sleep data for (typically the wake-up day)
    /// - Returns: The SleepSessionV2 for the night that ended on this display date, or nil if not found
    func fetchSleepSession(for displayDate: Date) async -> SleepSessionV2? {
        return await viewContext.perform {
            // Calculate the 6pm-6pm window in current timezone
            let window = self.calculate6pmTo6pmWindow(for: displayDate)
            
            // Query for sleep sessions whose sleep period overlaps this window
            let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: 
                "(startDateUTC >= %@ AND startDateUTC <= %@) OR (endDateUTC >= %@ AND endDateUTC <= %@) OR (startDateUTC <= %@ AND endDateUTC >= %@)",
                window.start as CVarArg, window.end as CVarArg,
                window.start as CVarArg, window.end as CVarArg,
                window.start as CVarArg, window.end as CVarArg
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "startDateUTC", ascending: false)]
            fetchRequest.fetchLimit = 1
            
            do {
                let sessions = try self.viewContext.fetch(fetchRequest)
                return sessions.first
            } catch {
                print("[SyncCoordinator] Error fetching SleepSessionV2 for \(displayDate): \(error)")
                return nil
            }
        }
    }
    
    /// Calculate the 6pm-6pm window for a given display date in current timezone
    /// - Parameter displayDate: The date to calculate the window for
    /// - Returns: A DateRange representing 6pm previous day to 6pm display date
    private func calculate6pmTo6pmWindow(for displayDate: Date) -> DateRange {
        let calendar = Calendar.current
        
        // Get 6pm on the display date
        let endOf6pmWindow = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: displayDate) ?? displayDate
        
        // Get 6pm on the previous day (start of window)
        let startOf6pmWindow = calendar.date(byAdding: .day, value: -1, to: endOf6pmWindow) ?? endOf6pmWindow
        
        return DateRange(start: startOf6pmWindow, end: endOf6pmWindow)
    }
}

// MARK: - Supporting Types

struct DateRange {
    let start: Date
    let end: Date
    
    var key: String {
        return "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
    }
}

enum SyncPriority {
    case background     // Low priority, can be deferred
    case userInitiated  // High priority, user is waiting
}

enum ChartType: String, CaseIterable {
    case sleepDebt = "sleepDebt"
    case sleepSummary = "sleepSummary"
    case sleepStages = "sleepStages"
    case sleepSchedule = "sleepSchedule"
    case heartRate = "heartRate"
    case hrv = "hrv"
    case heartRateHRV = "heartRateHRV"
    case correlations = "correlations"
    case dailyHabits = "dailyHabits"
}
