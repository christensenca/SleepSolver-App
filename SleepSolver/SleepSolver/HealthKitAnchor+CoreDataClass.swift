//
//  HealthKitAnchor+CoreDataClass.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import Foundation
import CoreData
import HealthKit

@objc(HealthKitAnchor)
public class HealthKitAnchor: NSManagedObject {
    
    /// Convenience method to get or create an anchor for a specific data type
    static func getAnchor(for dataType: String, context: NSManagedObjectContext) -> HealthKitAnchor? {
        let request: NSFetchRequest<HealthKitAnchor> = HealthKitAnchor.fetchRequest()
        request.predicate = NSPredicate(format: "dataType == %@", dataType)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching HealthKit anchor for \(dataType): \(error)")
            return nil
        }
    }
    
    /// Convenience method to create or update an anchor
    static func setAnchor(_ anchor: HKQueryAnchor?, for dataType: String, context: NSManagedObjectContext) {
        let existingAnchor = getAnchor(for: dataType, context: context) ?? HealthKitAnchor(context: context)
        
        existingAnchor.dataType = dataType
        existingAnchor.lastUpdated = Date()
        
        if let anchor = anchor {
            do {
                existingAnchor.anchor = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            } catch {
                print("Error archiving HealthKit anchor: \(error)")
                existingAnchor.anchor = nil
            }
        } else {
            existingAnchor.anchor = nil
        }
        
        do {
            try context.save()
        } catch {
            print("Error saving HealthKit anchor: \(error)")
        }
    }
    
    /// Get the HKQueryAnchor from stored data
    var hkQueryAnchor: HKQueryAnchor? {
        guard let anchorData = anchor else { return nil }
        
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchorData)
        } catch {
            print("Error unarchiving HealthKit anchor: \(error)")
            return nil
        }
    }
}
