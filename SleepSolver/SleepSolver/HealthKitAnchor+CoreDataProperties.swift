//
//  HealthKitAnchor+CoreDataProperties.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import Foundation
import CoreData

extension HealthKitAnchor {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HealthKitAnchor> {
        return NSFetchRequest<HealthKitAnchor>(entityName: "HealthKitAnchor")
    }

    @NSManaged public var anchor: Data?
    @NSManaged public var dataType: String
    @NSManaged public var lastUpdated: Date

}

extension HealthKitAnchor : Identifiable {

}
