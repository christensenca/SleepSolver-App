import Foundation
import CoreData

@objc(Workout)
public class Workout: NSManagedObject {
    
    /// Calculated property for duration in minutes
    var durationInMinutes: Double {
        return workoutLength / 60.0
    }
    
    /// Calculated property for distance in kilometers (if available)
    var distanceInKilometers: Double? {
        return distance > 0 ? distance / 1000.0 : nil
    }
    
    /// Formatted string for workout display
    var displayString: String {
        let duration = String(format: "%.0f min", durationInMinutes)
        if let distanceKm = distanceInKilometers {
            return "\(workoutType) - \(duration) (\(String(format: "%.1f km", distanceKm)))"
        } else {
            return "\(workoutType) - \(duration)"
        }
    }
}
