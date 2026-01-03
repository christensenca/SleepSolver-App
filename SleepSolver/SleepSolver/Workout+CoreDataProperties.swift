import Foundation
import CoreData

extension Workout {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Workout> {
        return NSFetchRequest<Workout>(entityName: "Workout")
    }

    @NSManaged public var uuid: UUID
    @NSManaged public var date: Date
    @NSManaged public var workoutType: String
    @NSManaged public var workoutLength: Double
    @NSManaged public var timeOfDay: String
    @NSManaged public var calories: Double
    @NSManaged public var distance: Double
    @NSManaged public var averageHeartRate: Double
    @NSManaged public var sleepSession: SleepSessionV2?

}

extension Workout : Identifiable {
    public var id: UUID { uuid }
}
