import Foundation
import CoreData

extension HabitRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HabitRecord> {
        return NSFetchRequest<HabitRecord>(entityName: "HabitRecord")
    }

    @NSManaged public var date: Date?
    @NSManaged public var entryDate: Date
    @NSManaged public var isResolved: Bool
    @NSManaged public var value: String?
    @NSManaged public var name: String
    @NSManaged public var definition: HabitDefinition
    @NSManaged public var sleepSession: SleepSessionV2?

    // Convenience accessors
    public var icon: String { return definition.icon }
}

extension HabitRecord : Identifiable {

}