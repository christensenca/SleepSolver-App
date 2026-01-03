//
//  SleepAnalysisIntegration.swift
//  SleepSolver
//
//  Created by Cade Christensen on 1/30/25.
//

import Foundation
import CoreData

/**
 * Example integration of SleepAnalysisEngine with the existing HealthKit sync flow.
 * This demonstrates how to integrate the authoritative sleep pipeline into your app.
 */
class SleepAnalysisIntegration {
    
    private let analysisEngine: SleepAnalysisEngine
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
        self.analysisEngine = SleepAnalysisEngine(context: context)
    }
    
    // MARK: - Integration Points
    
    /**
     * Call this to process any unresolved periods after new data has been saved to Core Data.
     * This is the primary method for triggering sleep analysis.
     */
    func performIncrementalSleepAnalysis() async {
        await context.perform {
            self.analysisEngine.runAnalysis()
            self.analysisEngine.runFinalization()
            print("[SleepAnalysisIntegration] ✅ Incremental analysis and finalization triggered.")
        }
    }
    
    // MARK: - Utility Methods
    
    /**
     * Fetches all SleepSessionV2 records for display in the UI.
     * These represent the authoritative sleep sessions.
     */
    func fetchAuthoritativeSleepSessions() throws -> [SleepSessionV2] {
        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "ownershipDay", ascending: false)]
        return try context.fetch(request)
    }
    
    /**
     * Fetches a specific sleep session for a given day.
     * Useful for UI components that need to display sleep data for a specific date.
     */
    func fetchSleepSession(for date: Date) throws -> SleepSessionV2? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        let request: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        request.predicate = NSPredicate(format: "ownershipDay == %@", startOfDay as NSDate)
        request.fetchLimit = 1
        
        return try context.fetch(request).first
    }
    
    /**
     * Debug helper: prints analysis statistics.
     */
    func printAnalysisStatistics() throws {
        let sessions = try fetchAuthoritativeSleepSessions()
        let totalPeriods = try fetchTotalSleepPeriods()
        let resolvedPeriods = try fetchResolvedSleepPeriods()
        
        print("📊 Sleep Analysis Statistics:")
        print("   Authoritative Sessions: \(sessions.count)")
        print("   Total Sleep Periods: \(totalPeriods)")
        print("   Resolved Periods: \(resolvedPeriods)")
        print("   Unresolved Periods: \(totalPeriods - resolvedPeriods)")
        
        for session in sessions.prefix(5) {
            let linkedCount = session.sourcePeriods?.count ?? 0
            print("   Session \(session.debugIdentifier): \(linkedCount) linked periods")
        }
    }
    
    // MARK: - Private Helpers
    
    private func fetchTotalSleepPeriods() throws -> Int {
        let request: NSFetchRequest<SleepPeriod> = SleepPeriod.fetchRequest()
        return try context.count(for: request)
    }
    
    private func fetchResolvedSleepPeriods() throws -> Int {
        let request: NSFetchRequest<SleepPeriod> = SleepPeriod.fetchRequest()
        // A period is considered "resolved" if it's linked to an authoritative session.
        request.predicate = NSPredicate(format: "sessionV2 != nil")
        return try context.count(for: request)
    }
}

// MARK: - Example Usage in App

/*
 Example of how to integrate this in your existing app:
 
 1. In your App Delegate or main coordinator:
 ```swift
 let sleepAnalysis = SleepAnalysisIntegration(context: persistentContainer.viewContext)
 ```
 
 2. In your HealthKit sync completion handler:
 ```swift
 // After syncing new sleep data from HealthKit
 Task {
     await sleepAnalysis.performIncrementalSleepAnalysis()
 }
 ```
 
 3. In your UI views:
 ```swift
 let sessions = try sleepAnalysis.fetchAuthoritativeSleepSessions()
 // Display sessions in your UI instead of raw SleepPeriod data
 ```
 */
