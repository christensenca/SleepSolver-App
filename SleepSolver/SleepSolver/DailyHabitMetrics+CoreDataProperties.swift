import Foundation
import CoreData

extension DailyHabitMetrics {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DailyHabitMetrics> {
        return NSFetchRequest<DailyHabitMetrics>(entityName: "DailyHabitMetrics")
    }

    @NSManaged public var date: Date?
    @NSManaged public var exerciseTime: Double
    @NSManaged public var steps: Double
    @NSManaged public var timeinDaylight: Double
    @NSManaged public var sleepSession: SleepSessionV2?

}

extension DailyHabitMetrics : Identifiable {

}
