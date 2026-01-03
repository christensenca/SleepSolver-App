import Foundation

enum ChartTimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case sixMonths = "6 Months"
    
    // Standardized date range calculation for all charts
    func dateRange() -> (start: Date, end: Date, numberOfDays: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let numberOfDays: Int
        switch self {
        case .week: numberOfDays = 7
        case .month: numberOfDays = 30
        case .sixMonths: numberOfDays = 180
        }
        
        // Consistent calculation: start is numberOfDays-1 days before today (inclusive)
        // This ensures we get exactly numberOfDays of data including today
        guard let startDate = calendar.date(byAdding: .day, value: -(numberOfDays - 1), to: today) else {
            return (today, today, 1)
        }
        
        return (startDate, today, numberOfDays)
    }
}
