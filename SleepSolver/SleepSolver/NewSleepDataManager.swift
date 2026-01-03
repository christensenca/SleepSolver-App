//
//  NewSleepDataManager.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import Foundation
import HealthKit
import CoreData
import CommonCrypto

/// Temporary struct representing a potential sleep period before it becomes a SleepPeriod entity
struct PotentialPeriod {
    let samples: [HKCategorySample]
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let sourceIdentifier: String
    let originalTimeZone: String
    
    init(samples: [HKCategorySample]) {
        guard !samples.isEmpty else {
            fatalError("PotentialPeriod cannot be created with empty samples array")
        }
        
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        self.samples = sortedSamples
        self.startDate = sortedSamples.first!.startDate
        self.endDate = sortedSamples.last!.endDate
        self.duration = endDate.timeIntervalSince(startDate)
        self.sourceIdentifier = sortedSamples.first!.sourceRevision.source.bundleIdentifier
        self.originalTimeZone = sortedSamples.first!.metadata?[HKMetadataKeyTimeZone] as? String ?? TimeZone.current.identifier
    }
    
    /// Generate deterministic ID for this period
    var stableID: String {
        let startDateString = ISO8601DateFormatter().string(from: startDate)
        return "\(sourceIdentifier)-\(startDateString)".sha256
    }
}

/// New timezone-tolerant sleep data manager using anchored queries
class NewSleepDataManager {
    static let shared = NewSleepDataManager()
    
    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current
    
    // HealthKit identifiers for the new system
    private let sleepAnalysisTypeIdentifier = HKCategoryTypeIdentifier.sleepAnalysis
    
    private init() {}
    
    // MARK: - Anchored Query Methods
    
    /// Fetches sleep data for onboarding - limited to the last 3 months using a simple date-range query
    /// - Parameters:
    ///   - context: The managed object context to perform operations on.
    ///   - completion: A closure called when the operation is complete, passing an optional error.
    func fetchOnboardingSleepData(context: NSManagedObjectContext, completion: @escaping (Error?) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: sleepAnalysisTypeIdentifier) else {
            completion(NSError(domain: "NewSleepDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sleep analysis type not available"]))
            return
        }

        // For onboarding, fetch exactly the last 3 months of data
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -3, to: endDate) else {
            completion(NSError(domain: "NewSleepDataManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate 3-month date range"]))
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        print("[NewSleepDataManager] Starting onboarding sleep data fetch for exactly 3 months (\(startDate) to \(endDate)).")
        
        // Use a simple sample query instead of anchored query for bounded date range
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { [weak self] query, samples, error in
            
            if let error = error {
                print("[NewSleepDataManager] Onboarding query error: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let self = self else {
                completion(NSError(domain: "NewSleepDataManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Manager was deallocated"]))
                return
            }
            
            let sampleCount = samples?.count ?? 0
            print("[NewSleepDataManager] Received \(sampleCount) samples for 3-month onboarding sync.")
            
            context.perform {
                if let samples = samples as? [HKCategorySample], !samples.isEmpty {
                    self.handleAddedSamples(samples, context: context)
                }
                
                // Update the anchor to current time since we've synced all data up to now
                // This ensures future incremental syncs start from the right point
                let currentAnchor = HKQueryAnchor(fromValue: Int(Date().timeIntervalSinceReferenceDate))
                HealthKitAnchor.setAnchor(currentAnchor, for: self.sleepAnalysisTypeIdentifier.rawValue, context: context)
                
                // Save context
                do {
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    print("[NewSleepDataManager] Error saving context after onboarding sync: \(error)")
                    completion(error)
                    return
                }

                print("[NewSleepDataManager] Finished onboarding sleep data fetch and updated anchor.")
                completion(nil)
            }
        }
        
        healthStore.execute(query)
    }

    /// Fetches new sleep data using anchored queries. Can perform a full historical sync or an incremental update.
    /// - Parameters:
    ///   - context: The managed object context to perform operations on.
    ///   - fetchAll: If true, fetches all historical data from HealthKit by repeatedly querying until no new data is returned. The anchor is not used for the initial query.
    ///   - completion: A closure called when the operation is complete, passing an optional error.
    func fetchNewSleepDataWithAnchoredQuery(context: NSManagedObjectContext, fetchAll: Bool = false, completion: @escaping (Error?) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: sleepAnalysisTypeIdentifier) else {
            completion(NSError(domain: "NewSleepDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sleep analysis type not available"]))
            return
        }

        // Determine the starting anchor. For a full sync, we start with no anchor. For incremental, we use the saved one.
        let initialAnchor = fetchAll ? nil : HealthKitAnchor.getAnchor(for: sleepAnalysisTypeIdentifier.rawValue, context: context)?.hkQueryAnchor
        
        print("[NewSleepDataManager] Starting sleep data fetch. Full sync: \(fetchAll).")
        
        // Create a predicate. If fetching all, no date predicate. Otherwise, limit to the last 210 days.
        let predicate: NSPredicate?
        if fetchAll {
            predicate = nil // No date restriction for a full historical sync
        } else {
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -210, to: endDate) ?? endDate
            predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        }
        
        // Start the recursive fetching process.
        fetchSleepDataRecursively(sleepType: sleepType, anchor: initialAnchor, fetchAll: fetchAll, context: context, predicate: predicate, completion: completion)
    }

    private func fetchSleepDataRecursively(sleepType: HKCategoryType, anchor: HKQueryAnchor?, fetchAll: Bool, context: NSManagedObjectContext, predicate: NSPredicate? = nil, completion: @escaping (Error?) -> Void) {
        
        // Set a limit. No limit for the first batch of a full sync, otherwise a reasonable limit.
        // HealthKit often imposes its own internal limit anyway.
        let limit = fetchAll ? HKObjectQueryNoLimit : 2000
        
        print("[NewSleepDataManager] Starting anchored query. FetchAll: \(fetchAll), Anchor: \(anchor?.description ?? "nil"), HasPredicate: \(predicate != nil)")

        let query = HKAnchoredObjectQuery(
            type: sleepType,
            predicate: predicate,
            anchor: anchor,
            limit: limit
        ) { [weak self, predicate] query, addedSamples, deletedSamples, newAnchor, error in
            
            if let error = error {
                print("[NewSleepDataManager] Anchored query error: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let self = self else {
                completion(NSError(domain: "NewSleepDataManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Manager was deallocated"]))
                return
            }
            
            let addedCount = addedSamples?.count ?? 0
            print("[NewSleepDataManager] Received \(addedCount) new samples and \(deletedSamples?.count ?? 0) deleted objects from HealthKit.")
            
            context.perform {
                // Process changes
                if let deletedSamples = deletedSamples, !deletedSamples.isEmpty {
                    self.handleDeletedSamples(deletedSamples, context: context)
                }
                if let addedSamples = addedSamples as? [HKCategorySample], !addedSamples.isEmpty {
                    self.handleAddedSamples(addedSamples, context: context)
                }
                
                // Save the new anchor regardless of sample count
                if let newAnchor = newAnchor {
                    HealthKitAnchor.setAnchor(newAnchor, for: self.sleepAnalysisTypeIdentifier.rawValue, context: context)
                }

                // Save context before next step
                do {
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    print("[NewSleepDataManager] Error saving context after processing batch: \(error)")
                    completion(error)
                    return
                }

                // Continue fetching if:
                // 1. fetchAll is true (full historical sync), OR 
                // 2. We have a predicate (date-limited sync like onboarding) and got data
                let hasPredicate = predicate != nil
                let shouldContinue = (fetchAll || hasPredicate) && addedCount > 0 && newAnchor != nil
                
                if shouldContinue, let nextAnchor = newAnchor {
                    self.fetchSleepDataRecursively(sleepType: sleepType, anchor: nextAnchor, fetchAll: fetchAll, context: context, predicate: predicate, completion: completion)
                } else {
                    // This is the exit condition for the recursion:
                    // 1. `fetchAll` was false (incremental sync)
                    // 2. `fetchAll` was true, but the last query returned 0 samples.
                    print("[NewSleepDataManager] Finished fetching sleep data.")
                    completion(nil)
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Sample Processing
    
    private func handleDeletedSamples(_ deletedSamples: [HKDeletedObject], context: NSManagedObjectContext) {
        print("[NewSleepDataManager] Processing \(deletedSamples.count) deleted objects.")
        
        for deletedObject in deletedSamples {
            // Find and delete the corresponding SleepSample
            let fetchRequest: NSFetchRequest<SleepSample> = SleepSample.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "uuid == %@", deletedObject.uuid as CVarArg)
            
            do {
                let samples = try context.fetch(fetchRequest)
                for sample in samples {
                    context.delete(sample)
                    
                    // Check if the sleep period should be updated or deleted
                    if let period = sample.sleepPeriod {
                        updateSleepPeriodAfterSampleDeletion(period, context: context)
                    }
                }
            } catch {
                print("[NewSleepDataManager] Error fetching sample for deletion: \(error)")
            }
        }
    }
    
    private func handleAddedSamples(_ addedSamples: [HKCategorySample], context: NSManagedObjectContext) {
        print("[NewSleepDataManager] Processing \(addedSamples.count) new samples.")
        
        // Filter samples: only com.apple.health bundle ID, Watch product types, and exclude .inBed
        let filteredSamples = addedSamples.filter { sample in
            // Check bundle identifier (case-insensitive)
            guard sample.sourceRevision.source.bundleIdentifier.lowercased().contains("com.apple.health") else {
                return false
            }
            
            // Check product type (prefer sourceRevision.productType, most reliable)
            guard let productType = sample.sourceRevision.productType,
                  productType.lowercased().contains("watch") else {
                return false
            }
            
            // Filter out .inBed samples (raw value 0)
            guard sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue else {
                return false
            }
            
            return true
        }
        
        print("[NewSleepDataManager] Filtered to \(filteredSamples.count) relevant samples.")
        
        // Group samples by potential periods (no more than 15 minutes apart)
        let potentialPeriods = groupSamplesIntoPotentialPeriods(filteredSamples)
        print("[NewSleepDataManager] Grouped samples into \(potentialPeriods.count) potential sleep periods.")
        
        for potentialPeriod in potentialPeriods {
            processPotentialPeriod(potentialPeriod, context: context)
        }
    }
    
    // MARK: - Period Processing
    
    private func groupSamplesIntoPotentialPeriods(_ samples: [HKCategorySample]) -> [PotentialPeriod] {
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        var periodSamples: [[HKCategorySample]] = []
        var currentPeriod: [HKCategorySample] = []
        
        for sample in sortedSamples {
            if let lastSample = currentPeriod.last {
                let gap = sample.startDate.timeIntervalSince(lastSample.endDate)
                if gap > 15 * 60 { // 15 minutes gap threshold
                    // Start a new period
                    if !currentPeriod.isEmpty {
                        periodSamples.append(currentPeriod)
                    }
                    currentPeriod = [sample]
                } else {
                    currentPeriod.append(sample)
                }
            } else {
                currentPeriod = [sample]
            }
        }
        
        if !currentPeriod.isEmpty {
            periodSamples.append(currentPeriod)
        }
        
        // Convert arrays of samples into PotentialPeriod structs
        return periodSamples.compactMap { samples in
            guard !samples.isEmpty else { return nil }
            return PotentialPeriod(samples: samples)
        }
    }
    
    private func processPotentialPeriod(_ potentialPeriod: PotentialPeriod, context: NSManagedObjectContext) {
        // Create deterministic ID: already computed in PotentialPeriod
        let periodID = potentialPeriod.stableID
        
        // Check if period already exists
        let fetchRequest: NSFetchRequest<SleepPeriod> = SleepPeriod.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", periodID)
        fetchRequest.fetchLimit = 1
        
        do {
            let existingPeriods = try context.fetch(fetchRequest)
            let period = existingPeriods.first ?? SleepPeriod(context: context)
            
            // Update period properties
            period.id = periodID
            period.startDateUTC = potentialPeriod.startDate
            period.endDateUTC = potentialPeriod.endDate
            period.duration = potentialPeriod.duration
            period.originalTimeZone = potentialPeriod.originalTimeZone
            period.sourceIdentifier = potentialPeriod.sourceIdentifier
            period.isMajorSleep = false // Will be determined later
            
            // Process each sample in the period
            for sample in potentialPeriod.samples {
                createOrUpdateSleepSample(from: sample, in: period, context: context)
            }
            
            // Check for mergeable periods after upserting this period
            checkForMergeablePeriodsAfterUpsert(period, context: context)
            
            // Calculate major sleep classification
            period.updateMajorSleepClassification()
            
        } catch {
            print("[NewSleepDataManager] Error processing potential period: \(error)")
        }
    }
    
    // MARK: - Period Merging Logic
    
    /// Check for and merge periods that should be continuous but were split by anchored query boundaries
    private func checkForMergeablePeriodsAfterUpsert(_ targetPeriod: SleepPeriod, context: NSManagedObjectContext) {
        // Find periods from the same source that might be mergeable
        let fetchRequest: NSFetchRequest<SleepPeriod> = SleepPeriod.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "sourceIdentifier == %@ AND id != %@", 
                                           targetPeriod.sourceIdentifier, targetPeriod.id)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "startDateUTC", ascending: true)]
        
        do {
            let candidatePeriods = try context.fetch(fetchRequest)
            var periodsToMerge: [SleepPeriod] = []
            
            // Check each candidate period for mergeability
            for candidatePeriod in candidatePeriods {
                if canMergePeriods(targetPeriod, candidatePeriod) {
                    periodsToMerge.append(candidatePeriod)
                }
            }
            
            if !periodsToMerge.isEmpty {
                // Include the target period in the merge
                periodsToMerge.append(targetPeriod)
                
                // Sort all periods by start time to determine merge order
                periodsToMerge.sort { $0.startDateUTC < $1.startDateUTC }
                
                // Merge all periods into the earliest one
                mergePeriodsIntoEarliest(periodsToMerge, context: context)
            }
            
        } catch {
            print("[NewSleepDataManager] Error checking for mergeable periods: \(error)")
        }
    }
    
    /// Determine if two periods can be merged based on time gap and other criteria
    private func canMergePeriods(_ period1: SleepPeriod, _ period2: SleepPeriod) -> Bool {
        // Must be from same source
        guard period1.sourceIdentifier == period2.sourceIdentifier else { return false }
        
        // Calculate the gap between the periods
        let earlierPeriod = period1.startDateUTC < period2.startDateUTC ? period1 : period2
        let laterPeriod = period1.startDateUTC < period2.startDateUTC ? period2 : period1
        
        let gap = laterPeriod.startDateUTC.timeIntervalSince(earlierPeriod.endDateUTC)
        
        // Merge if gap is 15 minutes or less (including overlaps which would be negative)
        return gap <= 15 * 60
    }
    
    /// Merge multiple periods into the earliest period, delete the others
    private func mergePeriodsIntoEarliest(_ periods: [SleepPeriod], context: NSManagedObjectContext) {
        guard periods.count > 1 else { return }
        
        let sortedPeriods = periods.sorted { $0.startDateUTC < $1.startDateUTC }
        let targetPeriod = sortedPeriods.first!
        let periodsToMerge = Array(sortedPeriods.dropFirst())
        
        print("[NewSleepDataManager] Merging \(periods.count) periods into one.")
        
        // Process periods that will be merged/deleted
        for period in periodsToMerge {
            if let session = period.analysisSession {
                // If target period doesn't have a session, link it to this session
                if targetPeriod.analysisSession == nil {
                    session.linkSleepPeriod(targetPeriod)
                }
                
                // Unlink the period that will be deleted
                session.unlinkSleepPeriod(period)
            }
        }
        
        // Collect all samples from periods to be merged
        var allSamples: [SleepSample] = Array(targetPeriod.samples)
        
        for period in periodsToMerge {
            // Move samples to target period
            for sample in period.samples {
                sample.sleepPeriod = targetPeriod
                allSamples.append(sample)
            }
            
            // Delete the merged period
            context.delete(period)
        }
        
        // Recalculate target period boundaries based on all samples
        if !allSamples.isEmpty {
            let sortedSamples = allSamples.sorted { $0.startDateUTC < $1.startDateUTC }
            targetPeriod.startDateUTC = sortedSamples.first!.startDateUTC
            targetPeriod.endDateUTC = sortedSamples.last!.endDateUTC
            targetPeriod.duration = targetPeriod.endDateUTC.timeIntervalSince(targetPeriod.startDateUTC)
            
            // Update the period ID to reflect the new true start time
            let startDateString = ISO8601DateFormatter().string(from: targetPeriod.startDateUTC)
            targetPeriod.id = "\(targetPeriod.sourceIdentifier)-\(startDateString)".sha256
            
            // Recalculate major sleep classification for merged period
            targetPeriod.updateMajorSleepClassification()
            
            // CRITICAL: Mark the target period as unresolved so incremental analysis will reprocess it
            targetPeriod.isResolved = false
            print("[NewSleepDataManager] Marked merged period as unresolved for re-analysis.")
        }
        
        // CRITICAL: Save all changes to ensure session updates and isResolved flags persist
        do {
            try context.save()
        } catch {
            print("[NewSleepDataManager] ❌ Failed to save period merge changes: \(error)")
        }
    }
    
    private func createOrUpdateSleepSample(from hkSample: HKCategorySample, in period: SleepPeriod, context: NSManagedObjectContext) {
        // Check if sample already exists
        let fetchRequest: NSFetchRequest<SleepSample> = SleepSample.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", hkSample.uuid as CVarArg)
        fetchRequest.fetchLimit = 1
        
        do {
            let existingSamples = try context.fetch(fetchRequest)
            let sample = existingSamples.first ?? SleepSample(context: context)
            
            // Update sample properties
            sample.uuid = hkSample.uuid
            sample.stage = Int16(hkSample.value)
            sample.startDateUTC = hkSample.startDate
            sample.endDateUTC = hkSample.endDate
            
            // Extract bundleID and productType
            sample.bundleID = hkSample.sourceRevision.source.bundleIdentifier
            
            // Try sourceRevision.productType (most reliable)
            if let productType = hkSample.sourceRevision.productType {
                sample.productType = productType
            } else {
                sample.productType = nil
            }
            
            sample.sleepPeriod = period
            
        } catch {
            print("[NewSleepDataManager] Error creating/updating sleep sample: \(error)")
        }
    }
    
    private func updateSleepPeriodAfterSampleDeletion(_ period: SleepPeriod, context: NSManagedObjectContext) {
        // Refresh the period's samples
        context.refresh(period, mergeChanges: true)
        
        if period.samples.isEmpty {
            // Delete the period if it has no samples
            context.delete(period)
        } else {
            // Update period duration and dates based on remaining samples
            let sortedSamples = period.samplesArray
            if let firstSample = sortedSamples.first, let lastSample = sortedSamples.last {
                period.startDateUTC = firstSample.startDateUTC
                period.endDateUTC = lastSample.endDateUTC
                period.duration = lastSample.endDateUTC.timeIntervalSince(firstSample.startDateUTC)
            }
        }
    }
}

// MARK: - String Extension for SHA256
extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { bytes in
            return bytes.withMemoryRebound(to: UInt8.self) { pointer in
                var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                CC_SHA256(pointer.baseAddress, CC_LONG(data.count), &result)
                return result
            }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
