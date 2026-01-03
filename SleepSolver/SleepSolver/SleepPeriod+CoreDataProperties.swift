//
//  SleepPeriod+CoreDataProperties.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import Foundation
import CoreData

extension SleepPeriod {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SleepPeriod> {
        return NSFetchRequest<SleepPeriod>(entityName: "SleepPeriod")
    }

    @NSManaged public var id: String
    @NSManaged public var startDateUTC: Date
    @NSManaged public var endDateUTC: Date
    @NSManaged public var duration: Double
    @NSManaged public var isMajorSleep: Bool
    @NSManaged public var isResolved: Bool
    @NSManaged public var originalTimeZone: String
    @NSManaged public var sourceIdentifier: String
    @NSManaged public var analysisSession: SleepSessionV2?
    @NSManaged public var samples: Set<SleepSample>

}

extension SleepPeriod : Identifiable {
    public var samplesArray: [SleepSample] {
        let set = samples as Set<SleepSample>
        return set.sorted { $0.startDateUTC < $1.startDateUTC }
    }
}
