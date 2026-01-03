//
//  StreaksViewModel.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import Foundation
import CoreData
import Combine
import SwiftUI

// MARK: - Streak Models

struct StreakData: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let bestStreak: Int // All-time best streak (persisted)
    let currentStreak: Int // Current active streak
    let dailyResults: [Bool] // 7 days, index 0 = oldest, index 6 = newest
    let streakType: StreakType
    let color: Color
    let isNewRecord: Bool // True if we just beat the previous record
    let description: String // Description of what counts for this streak
    
    var isActive: Bool {
        return currentStreak > 0
    }
    
    var bestThisWeek: Int {
        // Calculate the longest consecutive streak within the 7-day window
        var maxStreak = 0
        var currentConsecutive = 0
        
        for success in dailyResults {
            if success {
                currentConsecutive += 1
                maxStreak = max(maxStreak, currentConsecutive)
            } else {
                currentConsecutive = 0
            }
        }
        
        return maxStreak
    }
}

enum StreakType {
    case sleep
    case workout
    case habit
}

// MARK: - StreaksViewModel

@MainActor
class StreaksViewModel: ObservableObject {
    @Published var streakData: [StreakData] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private let viewContext: NSManagedObjectContext
    private let calendar = Calendar.current
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Sectioned Data
    
    var sleepStreaks: [StreakData] {
        return streakData.filter { $0.streakType == .sleep }
            .sorted { first, second in
                if first.currentStreak > 0 && second.currentStreak == 0 {
                    return true
                } else if first.currentStreak == 0 && second.currentStreak > 0 {
                    return false
                } else {
                    if first.bestStreak != second.bestStreak {
                        return first.bestStreak > second.bestStreak
                    }
                    return first.currentStreak > second.currentStreak
                }
            }
    }
    
    var fitnessStreaks: [StreakData] {
        let fitnessNames = ["Daily Workout", "Running", "Time in Daylight"]
        return streakData.filter { fitnessNames.contains($0.name) }
            .sorted { first, second in
                if first.currentStreak > 0 && second.currentStreak == 0 {
                    return true
                } else if first.currentStreak == 0 && second.currentStreak > 0 {
                    return false
                } else {
                    if first.bestStreak != second.bestStreak {
                        return first.bestStreak > second.bestStreak
                    }
                    return first.currentStreak > second.currentStreak
                }
            }
    }
    
    var habitStreaks: [StreakData] {
        let fitnessNames = ["Daily Workout", "Running", "Time in Daylight"]
        return streakData.filter { $0.streakType == .habit && !fitnessNames.contains($0.name) }
            .sorted { first, second in
                if first.currentStreak > 0 && second.currentStreak == 0 {
                    return true
                } else if first.currentStreak == 0 && second.currentStreak > 0 {
                    return false
                } else {
                    if first.bestStreak != second.bestStreak {
                        return first.bestStreak > second.bestStreak
                    }
                    return first.currentStreak > second.currentStreak
                }
            }
    }
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
    }
    
    // MARK: - Public Interface
    
    func loadStreakData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let streaks = try await calculateStreaks()
                await MainActor.run {
                    self.streakData = streaks
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error loading streak data: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Best Streak Persistence
    
    private func getBestStreak(for key: String) -> Int {
        return UserDefaults.standard.integer(forKey: "bestStreak_\(key)")
    }
    
    private func setBestStreak(_ value: Int, for key: String) {
        UserDefaults.standard.set(value, forKey: "bestStreak_\(key)")
        print("[StreaksViewModel] Updated best streak for '\(key)': \(value)")
    }
    
    private func createStreakData(name: String, key: String, icon: String, currentStreak: Int, dailyResults: [Bool], streakType: StreakType, color: Color, description: String) -> StreakData {
        let storedBestStreak = getBestStreak(for: key)
        
        // Create the streak data first so we can use its bestThisWeek computed property
        let tempStreakData = StreakData(
            name: name,
            icon: icon,
            bestStreak: storedBestStreak, // Will be updated below if needed
            currentStreak: currentStreak,
            dailyResults: dailyResults,
            streakType: streakType,
            color: color,
            isNewRecord: false, // Temporary value
            description: description
        )
        
        // The best streak is the maximum of: stored best, current streak, and best this week
        let newBest = max(storedBestStreak, max(currentStreak, tempStreakData.bestThisWeek))
        let isNewRecord = currentStreak > 0 && currentStreak == newBest
        
        print("[StreaksViewModel] Creating streak for '\(name)': currentStreak=\(currentStreak), storedBest=\(storedBestStreak), bestThisWeek=\(tempStreakData.bestThisWeek), newBest=\(newBest), isNewRecord=\(isNewRecord)")
        
        // Update best streak if we have a new record
        if newBest > storedBestStreak {
            setBestStreak(newBest, for: key)
        }
        
        // Return updated streak data with the correct best streak and new record flag
        return StreakData(
            name: name,
            icon: icon,
            bestStreak: newBest,
            currentStreak: currentStreak,
            dailyResults: dailyResults,
            streakType: streakType,
            color: color,
            isNewRecord: isNewRecord,
            description: description
        )
    }
    
    // MARK: - Private Methods
    
    private func calculateStreaks() async throws -> [StreakData] {
        // Get the past 7 days (including today)
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -6, to: today) else {
            throw NSError(domain: "StreaksViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not calculate date range"])
        }
        
        print("[StreaksViewModel] Loading streaks for date range: \(startDate) to \(today)")
        
        // Fetch sleep sessions for sleep-related streaks (use normal date range)
        let sleepSessions = try await loadSleepSessions(from: startDate, to: today)
        print("[StreaksViewModel] Loaded \(sleepSessions.count) sleep sessions for sleep streaks")
        
        // Fetch sleep sessions for activity-related streaks (offset by +1 day)
        guard let activityStartDate = calendar.date(byAdding: .day, value: 1, to: startDate),
              let activityEndDate = calendar.date(byAdding: .day, value: 1, to: today) else {
            throw NSError(domain: "StreaksViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not calculate activity date range"])
        }
        
        let activitySessions = try await loadSleepSessions(from: activityStartDate, to: activityEndDate)
        print("[StreaksViewModel] Loaded \(activitySessions.count) sleep sessions for activity streaks")
        
        var streaks: [StreakData] = []
        
        // Calculate sleep streaks (use normal sessions)
        streaks.append(contentsOf: calculateSleepStreaks(sessions: sleepSessions, startDate: startDate))
        
        // Calculate workout streaks (use offset sessions + live data for today)
        streaks.append(contentsOf: try await calculateWorkoutStreaks(sessions: activitySessions, startDate: startDate, endDate: today))
        
        // Calculate habit streaks (use offset sessions + live data for today)
        streaks.append(contentsOf: try await calculateHabitStreaks(sessions: activitySessions, startDate: startDate, endDate: today))
        
        // Ensure standard metrics are always shown (even if inactive)
        streaks.append(contentsOf: try await ensureStandardMetrics(sessions: activitySessions, startDate: startDate, endDate: today, existingStreaks: streaks))
        
        return streaks
    }
    
    private func loadSleepSessions(from startDate: Date, to endDate: Date) async throws -> [SleepSessionV2] {
        return try await viewContext.perform {
            let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            request.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay <= %@", startDate as NSDate, endDate as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SleepSessionV2.ownershipDay, ascending: true)]
            request.relationshipKeyPathsForPrefetching = ["habitMetrics", "manualHabits", "workouts"]
            request.returnsObjectsAsFaults = false
            
            return try self.viewContext.fetch(request)
        }
    }
    
    // MARK: - Standard Metrics Enforcement
    
    private func ensureStandardMetrics(sessions: [SleepSessionV2], startDate: Date, endDate: Date, existingStreaks: [StreakData]) async throws -> [StreakData] {
        var additionalStreaks: [StreakData] = []
        let existingNames = Set(existingStreaks.map { $0.name })
        
        // Standard metrics that should always be visible
        let standardMetrics = ["Daily Workout", "Running", "Time in Daylight"]
        
        for metricName in standardMetrics {
            if !existingNames.contains(metricName) {
                // Create inactive streak with all false daily results
                let inactiveResults = Array(repeating: false, count: 7)
                
                switch metricName {
                case "Daily Workout":
                    additionalStreaks.append(createStreakData(
                        name: "Daily Workout",
                        key: "dailyWorkout",
                        icon: "figure.run",
                        currentStreak: 0,
                        dailyResults: inactiveResults,
                        streakType: .workout,
                        color: .orange,
                        description: ""
                    ))
                case "Running":
                    additionalStreaks.append(createStreakData(
                        name: "Running",
                        key: "running",
                        icon: "figure.run.circle",
                        currentStreak: 0,
                        dailyResults: inactiveResults,
                        streakType: .workout,
                        color: .red,
                        description: ""
                    ))
                case "Time in Daylight":
                    additionalStreaks.append(createStreakData(
                        name: "Time in Daylight",
                        key: "time_in_daylight",
                        icon: "sun.max.fill",
                        currentStreak: 0,
                        dailyResults: inactiveResults,
                        streakType: .habit,
                        color: .yellow,
                        description: "≥ 60 minutes daylight"
                    ))
                default:
                    break
                }
            }
        }
        
        return additionalStreaks
    }
    
    // MARK: - Sleep Streaks
    
    private func calculateSleepStreaks(sessions: [SleepSessionV2], startDate: Date) -> [StreakData] {
        var streaks: [StreakData] = []
        print("[StreaksViewModel] calculateSleepStreaks called with \(sessions.count) sessions")
        
        // Helper to get user's sleep need from UserDefaults
        let userSleepNeed = UserDefaults.standard.double(forKey: "userSleepNeed")
        print("[StreaksViewModel] User sleep need: \(userSleepNeed)")
        guard userSleepNeed > 0 else {
            print("[StreaksViewModel] No user sleep need set, skipping sleep debt streak")
            // Still calculate high sleep score streak
            let highScoreResults = calculateDailyResults(sessions: sessions, startDate: startDate) { session in
                return session.sleepScore >= 90
            }
            
            let highScoreStreak = calculateCurrentStreak(dailyResults: highScoreResults)
            streaks.append(createStreakData(
                name: "Sleep Score 90+",
                key: "sleepScore90",
                icon: "star.circle",
                currentStreak: highScoreStreak,
                dailyResults: highScoreResults,
                streakType: .sleep,
                color: .green,
                description: ""
            ))
            
            return streaks
        }
        
        // Low Sleep Debt Streak (< 1 hour)
        let lowDebtResults = calculateDailyResults(sessions: sessions, startDate: startDate) { session in
            let actualSleepHours = session.totalSleepTime / 3600.0 // Convert seconds to hours
            let rawDeficit = userSleepNeed - actualSleepHours
            let dailyDebt = max(-1.0, min(2.0, rawDeficit)) // Apply daily limits as per SleepDebtChartView
            return dailyDebt < 1.0
        }
        
        let lowDebtStreak = calculateCurrentStreak(dailyResults: lowDebtResults)
        print("[StreaksViewModel] Low Sleep Debt: dailyResults = \(lowDebtResults), currentStreak = \(lowDebtStreak)")
        
        streaks.append(createStreakData(
            name: "Low Sleep Debt",
            key: "lowSleepDebt",
            icon: "moon.zzz",
            currentStreak: lowDebtStreak,
            dailyResults: lowDebtResults,
            streakType: .sleep,
            color: .blue,
            description: "Sleep debt < 1 hour"
        ))
        
        // High Sleep Score Streak (≥ 90)
        let highScoreResults = calculateDailyResults(sessions: sessions, startDate: startDate) { session in
            return session.sleepScore >= 90
        }
        
        let highScoreStreak = calculateCurrentStreak(dailyResults: highScoreResults)
        print("[StreaksViewModel] Sleep Score 90+: dailyResults = \(highScoreResults), currentStreak = \(highScoreStreak)")
        
        streaks.append(createStreakData(
            name: "Sleep Score 90+",
            key: "sleepScore90",
            icon: "star.circle",
            currentStreak: highScoreStreak,
            dailyResults: highScoreResults,
            streakType: .sleep,
            color: .green,
            description: ""
        ))
        
        return streaks
    }
    
    // MARK: - Workout Streaks
    
    private func calculateWorkoutStreaks(sessions: [SleepSessionV2], startDate: Date, endDate: Date) async throws -> [StreakData] {
        var streaks: [StreakData] = []
        
        // Workout Consistency Streak
        let workoutResults = try await calculateActivityDailyResults(sessions: sessions, startDate: startDate, endDate: endDate) { session in
            return (session.workouts?.count ?? 0) > 0
        } liveDataCheck: {
            // Check for today's workouts directly from CoreData
            return try await self.hasWorkoutToday()
        }
        
        let workoutStreak = calculateCurrentStreak(dailyResults: workoutResults)
        print("[StreaksViewModel] Daily Workout: dailyResults = \(workoutResults), currentStreak = \(workoutStreak)")
        
        streaks.append(createStreakData(
            name: "Daily Workout",
            key: "dailyWorkout",
            icon: "figure.run",
            currentStreak: workoutStreak,
            dailyResults: workoutResults,
            streakType: .workout,
            color: .orange,
            description: ""
        ))
        
        // Running Streak
        let runningResults = try await calculateActivityDailyResults(sessions: sessions, startDate: startDate, endDate: endDate) { session in
            guard let workouts = session.workouts as? Set<Workout> else { return false }
            return workouts.contains { workout in
                workout.workoutType.lowercased().contains("run") ||
                workout.workoutType.lowercased().contains("jog")
            }
        } liveDataCheck: {
            // Check for today's running workouts directly from CoreData
            return try await self.hasRunningWorkoutToday()
        }
        
        let runningStreak = calculateCurrentStreak(dailyResults: runningResults)
        print("[StreaksViewModel] Running: dailyResults = \(runningResults), currentStreak = \(runningStreak)")
        
        streaks.append(createStreakData(
            name: "Running",
            key: "running",
            icon: "figure.run.circle",
            currentStreak: runningStreak,
            dailyResults: runningResults,
            streakType: .workout,
            color: .red,
            description: ""
        ))
        
        return streaks
    }
    
    // MARK: - Habit Streaks
    
    private func calculateHabitStreaks(sessions: [SleepSessionV2], startDate: Date, endDate: Date) async throws -> [StreakData] {
        var streaks: [StreakData] = []
        
        // Find all unique habits that were logged in the past 7 days
        var habitNames: Set<String> = []
        
        // Collect from historical sessions
        for session in sessions {
            // Collect HealthKit habit names from DailyHabitMetrics
            if let habitMetrics = session.habitMetrics {
                // Only include Time in Daylight (≥ 60 minutes)
                if habitMetrics.timeinDaylight >= 60 {
                    habitNames.insert("Time in Daylight")
                }
            }
            
            // Collect manual habit names
            if let manualHabits = session.manualHabits as? Set<HabitRecord> {
                for habit in manualHabits {
                    if !habit.name.isEmpty {
                        habitNames.insert(habit.name)
                    }
                }
            }
        }
        
        // Collect habits from today's live data
        let todayHabits = try await getTodayHabits()
        habitNames.formUnion(todayHabits)
        
        print("[StreaksViewModel] Found \(habitNames.count) unique habits: \(habitNames)")
        
        // Create streak for each habit
        for habitName in habitNames.sorted() {
            let habitResults = try await calculateHabitDailyResults(sessions: sessions, startDate: startDate, endDate: endDate, habitName: habitName)
            
            // Only include habits that have activity in the last 7 days
            let hasActivity = habitResults.contains(true)
            guard hasActivity else { continue }
            
            let currentStreak = calculateCurrentStreak(dailyResults: habitResults)
            
            let habitKey = habitName.lowercased().replacingOccurrences(of: " ", with: "_")
            let streak = createStreakData(
                name: habitName,
                key: habitKey,
                icon: getHabitIcon(for: habitName),
                currentStreak: currentStreak,
                dailyResults: habitResults,
                streakType: .habit,
                color: getHabitColor(for: habitName),
                description: getHabitDescription(for: habitName)
            )
            
            streaks.append(streak)
        }
        
        return streaks
    }
    
    private func getTodayHabits() async throws -> Set<String> {
        return try await viewContext.perform {
            var habitNames: Set<String> = []
            
            // Today's activities go into tomorrow's sleep session
            let today = Calendar.current.startOfDay(for: Date())
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return habitNames }
            
            // Look for tomorrow's sleep session (which contains today's activities)
            let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            request.predicate = NSPredicate(format: "ownershipDay == %@", tomorrow as NSDate)
            request.relationshipKeyPathsForPrefetching = ["manualHabits", "habitMetrics"]
            request.fetchLimit = 1
            
            let sessions = try self.viewContext.fetch(request)
            guard let session = sessions.first else { return habitNames }
            
            // Get manual habit names
            if let manualHabits = session.manualHabits as? Set<HabitRecord> {
                for habit in manualHabits {
                    if !habit.name.isEmpty {
                        habitNames.insert(habit.name)
                    }
                }
            }
            
            // Get HealthKit habit names
            if let habitMetrics = session.habitMetrics {
                if habitMetrics.timeinDaylight >= 60 {
                    habitNames.insert("Time in Daylight")
                }
            }
            
            return habitNames
        }
    }
    
    private func calculateHabitDailyResults(sessions: [SleepSessionV2], startDate: Date, endDate: Date, habitName: String) async throws -> [Bool] {
        var results: [Bool] = []
        
        for i in 0..<7 {
            guard let currentDate = calendar.date(byAdding: .day, value: i, to: startDate) else {
                results.append(false)
                continue
            }
            
            var hasHabit = false
            
            // Check if this is today - if so, use live data
            if calendar.isDate(currentDate, inSameDayAs: endDate) {
                hasHabit = try await hasHabitToday(habitName: habitName)
            } else {
                // For historical days, find the sleep session that contains activities for this day
                // The session's ownershipDay would be currentDate + 1
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                    results.append(false)
                    continue
                }
                
                let session = sessions.first { session in
                    calendar.isDate(session.ownershipDay, inSameDayAs: nextDay)
                }
                
                if let session = session {
                    // Check HealthKit habits based on the habit name
                    if let habitMetrics = session.habitMetrics {
                        switch habitName {
                        case "Time in Daylight":
                            hasHabit = habitMetrics.timeinDaylight >= 60 // At least 60 minutes (1 hour)
                        default:
                            break
                        }
                    }
                    
                    // Check manual habits if not found in HealthKit
                    if !hasHabit, let manualHabits = session.manualHabits as? Set<HabitRecord> {
                        hasHabit = manualHabits.contains { (habit: HabitRecord) in
                            habit.name == habitName
                        }
                    }
                }
            }
            
            results.append(hasHabit)
        }
        
        return results
    }
    
    private func hasHabitToday(habitName: String) async throws -> Bool {
        return try await viewContext.perform {
            // Today's activities go into tomorrow's sleep session
            let today = Calendar.current.startOfDay(for: Date())
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return false }
            
            // Look for tomorrow's sleep session (which contains today's activities)
            let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            request.predicate = NSPredicate(format: "ownershipDay == %@", tomorrow as NSDate)
            request.relationshipKeyPathsForPrefetching = ["manualHabits", "habitMetrics"]
            request.fetchLimit = 1
            
            let sessions = try self.viewContext.fetch(request)
            guard let session = sessions.first else { return false }
            
            // Check HealthKit habits
            if let habitMetrics = session.habitMetrics {
                switch habitName {
                case "Time in Daylight":
                    return habitMetrics.timeinDaylight >= 60
                default:
                    break
                }
            }
            
            // Check manual habits
            if let manualHabits = session.manualHabits as? Set<HabitRecord> {
                return manualHabits.contains { habit in
                    habit.name == habitName
                }
            }
            
            return false
        }
    }
    
    
    // MARK: - Helper Methods
    
    private func calculateActivityDailyResults(sessions: [SleepSessionV2], startDate: Date, endDate: Date, condition: (SleepSessionV2) -> Bool, liveDataCheck: () async throws -> Bool) async throws -> [Bool] {
        var results: [Bool] = []
        
        for i in 0..<7 {
            guard let currentDate = calendar.date(byAdding: .day, value: i, to: startDate) else {
                results.append(false)
                continue
            }
            
            // Check if this is today - if so, use live data
            if calendar.isDate(currentDate, inSameDayAs: endDate) {
                let hasLiveData = try await liveDataCheck()
                results.append(hasLiveData)
            } else {
                // For historical days, find the sleep session that contains activities for this day
                // The session's ownershipDay would be currentDate + 1
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                    results.append(false)
                    continue
                }
                
                let session = sessions.first { session in
                    calendar.isDate(session.ownershipDay, inSameDayAs: nextDay)
                }
                
                if let session = session {
                    let result = condition(session)
                    results.append(result)
                } else {
                    results.append(false)
                }
            }
        }
        
        return results
    }
    
    private func hasWorkoutToday() async throws -> Bool {
        return try await viewContext.perform {
            // Today's activities go into tomorrow's sleep session
            let today = Calendar.current.startOfDay(for: Date())
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return false }
            
            // Look for tomorrow's sleep session (which contains today's activities)
            let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            request.predicate = NSPredicate(format: "ownershipDay == %@", tomorrow as NSDate)
            request.relationshipKeyPathsForPrefetching = ["workouts"]
            request.fetchLimit = 1
            
            let sessions = try self.viewContext.fetch(request)
            guard let session = sessions.first else { return false }
            
            return (session.workouts?.count ?? 0) > 0
        }
    }
    
    private func hasRunningWorkoutToday() async throws -> Bool {
        return try await viewContext.perform {
            // Today's activities go into tomorrow's sleep session
            let today = Calendar.current.startOfDay(for: Date())
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return false }
            
            // Look for tomorrow's sleep session (which contains today's activities)
            let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
            request.predicate = NSPredicate(format: "ownershipDay == %@", tomorrow as NSDate)
            request.relationshipKeyPathsForPrefetching = ["workouts"]
            request.fetchLimit = 1
            
            let sessions = try self.viewContext.fetch(request)
            guard let session = sessions.first else { return false }
            
            // Check if any workout is running/jogging
            guard let workouts = session.workouts as? Set<Workout> else { return false }
            return workouts.contains { workout in
                workout.workoutType.lowercased().contains("run") ||
                workout.workoutType.lowercased().contains("jog")
            }
        }
    }
    
    private func calculateDailyResults(sessions: [SleepSessionV2], startDate: Date, condition: (SleepSessionV2) -> Bool) -> [Bool] {
        var results: [Bool] = []
        
        for i in 0..<7 {
            guard let currentDate = calendar.date(byAdding: .day, value: i, to: startDate) else {
                results.append(false)
                continue
            }
            
            let session = sessions.first { session in
                calendar.isDate(session.ownershipDay, inSameDayAs: currentDate)
            }
            
            if let session = session {
                let result = condition(session)
                results.append(result)
            } else {
                results.append(false)
            }
        }
        
        return results
    }
    
    private func calculateCurrentStreak(dailyResults: [Bool]) -> Int {
        // Calculate current streak from the end (most recent day)
        var streak = 0
        
        for i in (0..<dailyResults.count).reversed() {
            if dailyResults[i] {
                streak += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    private func getHabitIcon(for habitName: String) -> String {
        let lowercaseName = habitName.lowercased()
        
        if lowercaseName.contains("water") || lowercaseName.contains("hydra") {
            return "drop.fill"
        } else if lowercaseName.contains("meditat") || lowercaseName.contains("mindful") {
            return "brain.head.profile"
        } else if lowercaseName.contains("alcohol") || lowercaseName.contains("drink") {
            return "wineglass"
        } else if lowercaseName.contains("caffeine") || lowercaseName.contains("coffee") {
            return "cup.and.saucer.fill"
        } else if lowercaseName.contains("step") {
            return "figure.walk"
        } else if lowercaseName.contains("daylight") || lowercaseName.contains("sun") {
            return "sun.max.fill"
        } else if lowercaseName.contains("exercise") || lowercaseName.contains("workout") {
            return "dumbbell.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private func getHabitColor(for habitName: String) -> Color {
        let lowercaseName = habitName.lowercased()
        
        if lowercaseName.contains("water") || lowercaseName.contains("hydra") {
            return .blue
        } else if lowercaseName.contains("meditat") || lowercaseName.contains("mindful") {
            return .purple
        } else if lowercaseName.contains("alcohol") || lowercaseName.contains("drink") {
            return .red
        } else if lowercaseName.contains("caffeine") || lowercaseName.contains("coffee") {
            return .brown
        } else if lowercaseName.contains("step") {
            return .green
        } else if lowercaseName.contains("daylight") || lowercaseName.contains("sun") {
            return .yellow
        } else if lowercaseName.contains("exercise") || lowercaseName.contains("workout") {
            return .orange
        } else {
            return .gray
        }
    }
    
    private func getHabitDescription(for habitName: String) -> String {
        let lowercaseName = habitName.lowercased()
        
        if lowercaseName.contains("daylight") || lowercaseName.contains("sun") {
            return "≥ 60 minutes daylight"
        } else if lowercaseName.contains("water") || lowercaseName.contains("hydra") {
            return "Daily hydration logged"
        } else if lowercaseName.contains("meditat") || lowercaseName.contains("mindful") {
            return "Meditation or mindfulness"
        } else if lowercaseName.contains("alcohol") || lowercaseName.contains("drink") {
            return "Alcohol consumption logged"
        } else if lowercaseName.contains("caffeine") || lowercaseName.contains("coffee") {
            return "Caffeine intake logged"
        } else if lowercaseName.contains("step") {
            return "Daily step goal met"
        } else if lowercaseName.contains("exercise") || lowercaseName.contains("workout") {
            return "Exercise session logged"
        } else {
            return "Habit completed"
        }
    }
}
