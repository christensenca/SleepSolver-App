import Foundation
import Combine
import CoreData
import SwiftUI
import HealthKit

// Represents a HealthKit metric for display
struct HealthKitDisplayItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    var displayValue: String // "123 steps", "45 min", etc.

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Equatable conformance (needed for Hashable)
    static func == (lhs: HealthKitDisplayItem, rhs: HealthKitDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

// Represents a manual habit for display
struct ManualHabitDisplayItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    var displayValue: String // "Yes", custom value, etc.

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Equatable conformance (needed for Hashable)
    static func == (lhs: ManualHabitDisplayItem, rhs: ManualHabitDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

// Represents a workout item for display
struct WorkoutDisplayItem: Identifiable, Hashable {
    let id = UUID()
    let workoutType: String
    let duration: String
    let timeOfDay: String
    let calories: String?
    let distance: String?
    let heartRate: String?

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Equatable conformance (needed for Hashable)
    static func == (lhs: WorkoutDisplayItem, rhs: WorkoutDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

// Represents an available unlinked habit for display (for today's view)
struct UnlinkedHabitDisplayItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    // let habitDefinition: HabitDefinition // Temporarily commented out

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Equatable conformance (needed for Hashable)
    static func == (lhs: UnlinkedHabitDisplayItem, rhs: UnlinkedHabitDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class DailyHabitsViewModel: ObservableObject {
    @AppStorage("useImperialUnits") private var useImperialUnits: Bool = true

    @Published var healthKitItems: [HealthKitDisplayItem] = []
    @Published var manualHabitItems: [ManualHabitDisplayItem] = []
    @Published var workoutItems: [WorkoutDisplayItem] = []
    @Published var unlinkedHabitItems: [UnlinkedHabitDisplayItem] = [] // New: Show available habits for today
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var canAddHabits: Bool = true // Controls whether habits can be added (today or past day with session)

    private let viewContext: NSManagedObjectContext
    private let healthKitManager: HealthKitManager
    private let nightlySleepViewModel: NightlySleepViewModel
    private var cancellables = Set<AnyCancellable>()
    private let calendar = Calendar.current

    // Timer for automatic refresh of today's data (live HealthKit data)
    private var todayRefreshTimer: Timer?
    private var currentDate: Date?

    init(context: NSManagedObjectContext, nightlySleepViewModel: NightlySleepViewModel) {
        self.viewContext = context
        self.healthKitManager = HealthKitManager.shared
        self.nightlySleepViewModel = nightlySleepViewModel
    }
    
    deinit {
        todayRefreshTimer?.invalidate()
    }

    // MARK: - Public Interface
    
    // Allow access to sleep sessions for wind down heart rate functionality
    func getSleepSession(for date: Date) -> SleepSessionV2? {
        return nightlySleepViewModel.sleepSession(for: date)
    }

    // Main function to load data for a specific date
    func loadData(for date: Date) {
        isLoading = true
        errorMessage = nil
        currentDate = date
        
        // Setup auto-refresh for today's data (live HealthKit data)
        setupTodayRefreshTimer(for: date)
        
        let startOfDay = calendar.startOfDay(for: date)
        let isToday = calendar.isDateInToday(date)

        if isToday {
            // For today: show live HealthKit data and Core Data for manual habits
            loadTodayData(date: startOfDay)
        } else {
            // For past days: show finalized data from SleepSessionV2 if available
            loadPastDayData(displayDate: startOfDay)
        }
    }
    
    // MARK: - Today's Data (Live)
    
    private func loadTodayData(date: Date) {
        let startOfToday = calendar.startOfDay(for: date)
        let currentTime = Date()
        
        // For today, habits can always be added
        self.canAddHabits = true
        
        // Fetch live HealthKit data
        healthKitManager.fetchHabitMetrics(startDate: startOfToday, endDate: currentTime) { [weak self] habitMetrics, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let error = error {
                    // Check if this is a "no data" error vs a real error
                    let errorString = error.localizedDescription.lowercased()
                    if errorString.contains("no data available") || 
                       errorString.contains("no samples") ||
                       errorString.contains("predicate") ||
                       errorString.contains("not authorized") ||
                       errorString.contains("denied") ||
                       errorString.contains("permission") ||
                       errorString.contains("no data") ||
                       errorString.contains("not available") ||
                       (error as NSError).code == 5 { // HKErrorNoData
                        // Gracefully handle "no data" or authorization issues - don't show error, just show empty state
                        print("[DailyHabitsViewModel] No habit data available yet today: \(error.localizedDescription)")
                        self.healthKitItems = []
                    } else {
                        // Real error - show it to user
                        self.errorMessage = "Error fetching live habit data: \(error.localizedDescription)"
                        self.isLoading = false
                        return
                    }
                } else {
                    // Create HealthKit display items
                    self.healthKitItems = self.createHealthKitDisplayItems(from: habitMetrics)
                }
                
                // Fetch manual habits and workouts
                await self.loadManualHabitsAndWorkouts(for: date, isToday: true)
            }
        }
    }
    
    // MARK: - Past Day Data (Finalized)
    
    private func loadPastDayData(displayDate: Date) {
        // For past days, get the sleep session for the day AFTER the display date
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: displayDate) else {
            self.errorMessage = "Error calculating next day"
            self.isLoading = false
            return
        }
        
        Task { @MainActor in
            let session = nightlySleepViewModel.sleepSession(for: nextDay)
            
            if let session = session, let habitMetrics = session.habitMetrics {
                // Session exists with finalized HealthKit data
                self.healthKitItems = self.createHealthKitDisplayItems(from: habitMetrics)
                self.canAddHabits = true // Past day with session - habits can be added retroactively
                
                // Load manual habits and workouts from session
                await self.loadManualHabitsAndWorkouts(for: displayDate, session: session)
            } else {
                // No session or no finalized data - show NO data for past days (consistent behavior)
                self.healthKitItems = []
                self.manualHabitItems = []
                self.workoutItems = []
                self.unlinkedHabitItems = []
                self.canAddHabits = false // Past day without session - habits cannot be added
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Manual Habits and Workouts
    
    // MARK: - Unlinked Habits for Today
    
    private func fetchUnlinkedHabits(for date: Date) async -> [UnlinkedHabitDisplayItem] {
        return await viewContext.perform { [weak self] in
            guard let self = self else { return [] }
            
            do {
                // Fetch all non-archived habit definitions
                let definitionsFetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                definitionsFetchRequest.predicate = NSPredicate(format: "isArchived == NO")
                definitionsFetchRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \HabitDefinition.sortOrder, ascending: true),
                    NSSortDescriptor(keyPath: \HabitDefinition.name, ascending: true)
                ]
                let allDefinitions = try self.viewContext.fetch(definitionsFetchRequest)
                
                // Fetch existing records for this date
                let recordsFetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
                recordsFetchRequest.predicate = NSPredicate(format: "date == %@", date as NSDate)
                let existingRecords = try self.viewContext.fetch(recordsFetchRequest)
                let existingDefinitionNames = Set(existingRecords.map { $0.definition.name })
                
                // Filter out definitions that already have records for this date
                let unlinkedDefinitions = allDefinitions.filter { definition in
                    !existingDefinitionNames.contains(definition.name)
                }
                
                // Create display items for unlinked habits
                return unlinkedDefinitions.map { definition in
                    UnlinkedHabitDisplayItem(
                        name: definition.name,
                        icon: definition.icon
                        // habitDefinition: definition // Temporarily commented out
                    )
                }
            } catch {
                print("[DailyHabitsViewModel] Error fetching unlinked habits: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    private func loadManualHabitsAndWorkouts(for date: Date, isToday: Bool = false, session: SleepSessionV2? = nil) async {
        // Fetch manual habits - different logic for today vs past days
        let manualItems: [ManualHabitDisplayItem] = await viewContext.perform { [weak self] in
            guard let self = self else { return [] }
            
            do {
                if isToday {
                    // For today: Fetch all habit records for this date (including unresolved ones)
                    let recordsFetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
                    recordsFetchRequest.predicate = NSPredicate(format: "date == %@", date as NSDate)
                    let records = try self.viewContext.fetch(recordsFetchRequest)
                    
                    // Create manual habit display items
                    return records.compactMap { record -> ManualHabitDisplayItem? in
                        let definition = record.definition
                        return ManualHabitDisplayItem(
                            name: definition.name,
                            icon: definition.icon,
                            displayValue: record.value ?? "Yes"
                        )
                    }
                } else {
                    // For past days: Only show habits that are linked to the session (same as HealthKit/workouts)
                    // session is guaranteed to be non-nil for past days now
                    guard let session = session else {
                        print("[DailyHabitsViewModel] No session for past day \(date) - no habits shown")
                        return []
                    }
                    
                    // Fetch only habit records that are linked to this session
                    let recordsFetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
                    recordsFetchRequest.predicate = NSPredicate(format: "sleepSession == %@", session)
                    let records = try self.viewContext.fetch(recordsFetchRequest)
                    
                    print("[DailyHabitsViewModel] Found \(records.count) habits linked to session for \(date)")
                    
                    // Create manual habit display items
                    return records.compactMap { record -> ManualHabitDisplayItem? in
                        let definition = record.definition
                        return ManualHabitDisplayItem(
                            name: definition.name,
                            icon: definition.icon,
                            displayValue: record.value ?? "Yes"
                        )
                    }
                }
            } catch {
                Task { @MainActor in
                    self.errorMessage = "Error loading manual habits: \(error.localizedDescription)"
                    self.isLoading = false
                }
                return []
            }
        }
        
        // Fetch unlinked habits for today only (separate call)
        let unlinkedItems: [UnlinkedHabitDisplayItem] = [] // Temporarily disabled
        // if isToday {
        //     unlinkedItems = await self.fetchUnlinkedHabits(for: date)
        // } else {
        //     unlinkedItems = []
        // }
        
        // Load workouts
        if let session = session {
            // Use workouts from session (finalized data) - only for past days with sessions
            let workouts = session.workouts?.allObjects as? [Workout] ?? []
            let workoutItems = workouts.map { workout in
                self.createWorkoutDisplayItem(from: workout)
            }
            
            self.manualHabitItems = manualItems
            self.workoutItems = workoutItems
            self.unlinkedHabitItems = unlinkedItems
            self.isLoading = false
        } else if isToday {
            // For today, fetch live workout data from HealthKit
            self.healthKitManager.fetchWorkouts(startDate: date, endDate: Date()) { workoutData, error in
                Task { @MainActor in
                    if let error = error {
                        print("[DailyHabitsViewModel] ❌ Error fetching live workouts: \(error.localizedDescription)")
                        self.workoutItems = []
                    } else {
                        let workoutItems = (workoutData ?? []).map { data in
                            self.createWorkoutDisplayItem(from: data)
                        }
                        self.workoutItems = workoutItems
                    }
                    
                    self.manualHabitItems = manualItems
                    self.unlinkedHabitItems = unlinkedItems
                    self.isLoading = false
                }
            }
        } else {
            // This case should no longer be reached since loadPastDayData now handles session-less past days
            print("[DailyHabitsViewModel] ⚠️ Unexpected case: past day without session in loadManualHabitsAndWorkouts")
            self.manualHabitItems = []
            self.workoutItems = []
            self.unlinkedHabitItems = []
            self.isLoading = false
        }
    }
    
    // MARK: - Display Item Creation
    
    private func createHealthKitDisplayItems(from metrics: HabitMetrics?) -> [HealthKitDisplayItem] {
        guard let metrics = metrics else { return [] }
        
        var items: [HealthKitDisplayItem] = []
        
        // Steps
        if metrics.steps > 0 {
            items.append(HealthKitDisplayItem(
                name: "Steps",
                icon: "figure.walk",
                displayValue: "\(Int(metrics.steps)) steps"
            ))
        }
        
        // Exercise Time
        if metrics.exerciseTime > 0 {
            items.append(HealthKitDisplayItem(
                name: "Exercise Time",
                icon: "figure.run",
                displayValue: "\(Int(metrics.exerciseTime)) min"
            ))
        }
        
        // Time in Daylight
        if metrics.timeInDaylight > 0 {
            items.append(HealthKitDisplayItem(
                name: "Time in Daylight",
                icon: "sun.max.fill",
                displayValue: "\(Int(metrics.timeInDaylight)) min"
            ))
        }
        
        return items
    }
    
    private func createHealthKitDisplayItems(from metrics: DailyHabitMetrics) -> [HealthKitDisplayItem] {
        var items: [HealthKitDisplayItem] = []
        
        // Steps
        if metrics.steps > 0 {
            items.append(HealthKitDisplayItem(
                name: "Steps",
                icon: "figure.walk",
                displayValue: "\(Int(metrics.steps)) steps"
            ))
        }
        
        // Exercise Time
        if metrics.exerciseTime > 0 {
            items.append(HealthKitDisplayItem(
                name: "Exercise Time",
                icon: "figure.run",
                displayValue: "\(Int(metrics.exerciseTime)) min"
            ))
        }
        
        // Time in Daylight
        if metrics.timeinDaylight > 0 {
            items.append(HealthKitDisplayItem(
                name: "Time in Daylight",
                icon: "sun.max.fill",
                displayValue: "\(Int(metrics.timeinDaylight)) min"
            ))
        }
        
        return items
    }
    
    private func createWorkoutDisplayItem(from workout: Workout) -> WorkoutDisplayItem {
        // Format duration
        let durationMinutes = Int(workout.workoutLength / 60)
        let duration = "\(durationMinutes) min"
        
        // Format optional fields
        let calories = workout.calories > 0 ? "\(Int(workout.calories)) cal" : nil
        // Convert from meters (stored) to miles/km for display based on user preference
        let distance = workout.distance > 0 ? formatDistance(workout.distance) : nil
        let heartRate = workout.averageHeartRate > 0 ? "\(Int(workout.averageHeartRate)) bpm" : nil
        
        return WorkoutDisplayItem(
            workoutType: workout.workoutType,
            duration: duration,
            timeOfDay: workout.timeOfDay,
            calories: calories,
            distance: distance,
            heartRate: heartRate
        )
    }
    
    private func createWorkoutDisplayItem(from workoutData: WorkoutData) -> WorkoutDisplayItem {
        // Format duration
        let durationMinutes = Int(workoutData.workoutLength / 60)
        let duration = "\(durationMinutes) min"
        
        // Format optional fields
        let calories = (workoutData.calories != nil && workoutData.calories! > 0) ? "\(Int(workoutData.calories!)) cal" : nil
        let distance = (workoutData.distance != nil && workoutData.distance! > 0) ? formatDistance(workoutData.distance!) : nil
        let heartRate = (workoutData.averageHeartRate != nil && workoutData.averageHeartRate! > 0) ? "\(Int(workoutData.averageHeartRate!)) bpm" : nil
        
        return WorkoutDisplayItem(
            workoutType: workoutData.workoutType,
            duration: duration,
            timeOfDay: workoutData.timeOfDay,
            calories: calories,
            distance: distance,
            heartRate: heartRate
        )
    }
    
    // MARK: - Distance Formatting Helper
    
    /// Format distance from meters to miles or kilometers based on user preference
    private func formatDistance(_ distanceInMeters: Double) -> String {
        if useImperialUnits {
            // Convert meters to miles
            let miles = distanceInMeters / 1609.34
            return String(format: "%.1f mi", miles)
        } else {
            // Convert meters to kilometers
            let kilometers = distanceInMeters / 1000.0
            return String(format: "%.1f km", kilometers)
        }
    }
    
    // MARK: - Manual Habit Management
    
    func addUnlinkedHabit(_ unlinkedItem: UnlinkedHabitDisplayItem, date: Date) {
        updateHabitRecord(habitName: unlinkedItem.name, icon: unlinkedItem.icon, date: date)
    }
    
    func updateHabitRecord(habitName: String, icon: String, date: Date) {
        // Guard against adding habits when not allowed
        guard canAddHabits else {
            print("[DailyHabitsViewModel] ❌ Cannot add habits for this date - no session available")
            self.errorMessage = "Cannot add habits for days without sleep data"
            return
        }
        
        viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                // Find or create habit definition
                let definitionFetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                definitionFetchRequest.predicate = NSPredicate(format: "name == %@", habitName)
                definitionFetchRequest.fetchLimit = 1
                
                let definitions = try self.viewContext.fetch(definitionFetchRequest)
                let definition: HabitDefinition
                
                if let existingDefinition = definitions.first {
                    definition = existingDefinition
                } else {
                    // Create new definition
                    definition = HabitDefinition(context: self.viewContext)
                    definition.name = habitName
                    definition.icon = icon
                    definition.isArchived = false
                    definition.sortOrder = 0
                }
                
                // Check if record already exists for this date
                let recordFetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
                recordFetchRequest.predicate = NSPredicate(format: "name == %@ AND date == %@", habitName, date as NSDate)
                recordFetchRequest.fetchLimit = 1
                
                let existingRecords = try self.viewContext.fetch(recordFetchRequest)
                
                if existingRecords.isEmpty {
                    // Create new record
                    let newRecord = HabitRecord(context: self.viewContext)
                    newRecord.name = habitName
                    newRecord.value = "Yes"
                    newRecord.date = date
                    newRecord.entryDate = Date()
                    newRecord.isResolved = false
                    newRecord.definition = definition
                    
                    print("[DailyHabitsViewModel] ✅ Created habit record for '\(habitName)' on \(date)")
                } else {
                    print("[DailyHabitsViewModel] ⚠️ Habit record for '\(habitName)' already exists for \(date)")
                }
                
                try self.viewContext.save()
                
                // Reload data
                Task { @MainActor in
                    self.loadData(for: date)
                }
                
            } catch {
                Task { @MainActor in
                    self.errorMessage = "Error saving habit: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func removeHabitRecord(habitName: String, date: Date) {
        viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            do {
                let fetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "name == %@ AND date == %@", habitName, date as NSDate)
                
                let records = try self.viewContext.fetch(fetchRequest)
                for record in records {
                    self.viewContext.delete(record)
                }
                
                try self.viewContext.save()
                
                // Reload data
                Task { @MainActor in
                    self.loadData(for: date)
                }
                
            } catch {
                Task { @MainActor in
                    self.errorMessage = "Error removing habit: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Auto-refresh for today
    
    private func setupTodayRefreshTimer(for date: Date) {
        // Clear any existing timer
        todayRefreshTimer?.invalidate()
        todayRefreshTimer = nil

        // Only set up auto-refresh for today's date (for live HealthKit data)
        if calendar.isDateInToday(date) {
            // Refresh every 5 minutes for today's live data updates
            todayRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshTodayLiveData()
                }
            }
        }
    }
    
    private func refreshTodayLiveData() {
        guard let currentDate = currentDate, calendar.isDateInToday(currentDate) else { return }
        
        print("[DailyHabitsViewModel] Auto-refreshing today's live data")
        loadTodayData(date: currentDate)
    }
}
