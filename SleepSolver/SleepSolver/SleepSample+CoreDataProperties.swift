//
//  SleepSample+CoreDataProperties.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import Foundation
import CoreData

extension SleepSample {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SleepSample> {
        return NSFetchRequest<SleepSample>(entityName: "SleepSample")
    }

    @NSManaged public var uuid: UUID
    @NSManaged public var stage: Int16
    @NSManaged public var startDateUTC: Date
    @NSManaged public var endDateUTC: Date
    @NSManaged public var bundleID: String?
    @NSManaged public var productType: String?
    @NSManaged public var sleepPeriod: SleepPeriod?

}

extension SleepSample : Identifiable {
    public var id: UUID { return uuid }
}
