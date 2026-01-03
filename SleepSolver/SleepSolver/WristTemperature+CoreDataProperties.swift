//
//  WristTemperature+CoreDataProperties.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/30/25.
//
//

import Foundation
import CoreData


extension WristTemperature {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WristTemperature> {
        return NSFetchRequest<WristTemperature>(entityName: "WristTemperature")
    }

    @NSManaged public var uuid: UUID
    @NSManaged public var date: Date
    @NSManaged public var value: Double
    @NSManaged public var isResolved: Bool
    @NSManaged public var session: SleepSessionV2?

}

extension WristTemperature : Identifiable {

}
