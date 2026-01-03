import Foundation
import CoreData

extension HabitDefinition {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HabitDefinition> {
        return NSFetchRequest<HabitDefinition>(entityName: "HabitDefinition")
    }

    @NSManaged public var icon: String
    @NSManaged public var isArchived: Bool
    @NSManaged public var name: String
    @NSManaged public var sortOrder: Int16
}

extension HabitDefinition : Identifiable {

}