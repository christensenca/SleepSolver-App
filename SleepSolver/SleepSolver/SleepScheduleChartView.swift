import SwiftUI
import Charts
import Foundation

struct SleepScheduleChartView: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    @State private var selectedTimeRange: ChartTimeRange = .week
    @State private var showInfo: Bool = false
    
    // Struct to hold a single continuous block of sleep time
    struct SleepBlock: Identifiable {
        let id = UUID()
        let startHour: Double
        let endHour: Double
    }
    
    // Struct to hold sleep session data for each day, including potentially multiple blocks
    struct SleepSessionData: Identifiable {
        let id = UUID()
        let date: Date
        let blocks: [SleepBlock]
        let originalStartHour: Double?
        let originalEndHour: Double?
    }
    
    // Number of days to show in the chart based on selected time range
    private var numberOfDays: Int {
        switch selectedTimeRange {
        case .week:
            return 7
        case .month:
            return 30
        case .sixMonths:
            return 180
        }
    }
    
    // Compute sleep sessions from view model
    private var sleepSessions: [SleepSessionData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var sessions: [SleepSessionData] = []
        
        // Determine the Y-axis range which is needed to process the sessions
        let yRange = yAxisRange
        let yAxisStartHour = yRange.lowerBound
        
        for i in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - i), to: today) {
                let key = viewModel.cacheKey(for: date)
                let sessionOptional = viewModel.sleepSessions[key]
                
                if let sessionData = sessionOptional as? SleepSessionV2 {
                    let startTime = sessionData.startDateUTC
                    let endTime = sessionData.endDateUTC
                    
                    let startHour = getHourFromDate(startTime)
                    var endHour = getHourFromDate(endTime)
                    
                    if endHour < startHour {
                        endHour += 24
                    }
                    
                    var blocks: [SleepBlock] = []
                    
                    // Normalize hours to be within the y-axis range (0-24)
                    let normStart = normalizeHour(startHour, relativeTo: yAxisStartHour)
                    let normEnd = normalizeHour(endHour, relativeTo: yAxisStartHour)
                    
                    // Check if the block wraps around the 24-hour y-axis
                    if normStart > normEnd { // This indicates a wrap
                        // First part of the bar: from start to the top of the chart
                        blocks.append(SleepBlock(startHour: normStart, endHour: 24))
                        // Second part of the bar: from the bottom of the chart to the end
                        blocks.append(SleepBlock(startHour: 0, endHour: normEnd))
                    } else { // The block fits entirely within the view
                        blocks.append(SleepBlock(startHour: normStart, endHour: normEnd))
                    }

                    sessions.append(SleepSessionData(
                        date: date,
                        blocks: blocks,
                        originalStartHour: startHour,
                        originalEndHour: endHour
                    ))
                } else {
                    // Add entry with empty blocks for missing data
                    sessions.append(SleepSessionData(
                        date: date,
                        blocks: [],
                        originalStartHour: nil,
                        originalEndHour: nil
                    ))
                }
            }
        }
        
        return sessions.sorted { $0.date < $1.date }
    }

    // Get sessions with data only (for calculating averages and Y-axis range)
    private var sessionsWithData: [SleepSessionData] {
        return sleepSessions.filter { !$0.blocks.isEmpty }
    }

    // The most recent session with data, used to anchor the Y-axis
    private var anchorSession: SleepSessionV2? {
        let sortedSessions = viewModel.sleepSessions.values
            .compactMap { $0 }
            .sorted { $0.startDateUTC > $1.startDateUTC }
        return sortedSessions.first
    }

    // Dynamic Y-axis range based on the most recent sleep session
    private var yAxisRange: ClosedRange<Double> {
        guard let lastSession = anchorSession else {
            return 18...42 // Default: 6 PM to 6 PM next day (24h window)
        }

        let startHour = getHourFromDate(lastSession.startDateUTC)
        var endHour = getHourFromDate(lastSession.endDateUTC)

        if endHour < startHour {
            endHour += 24
        }

        let midpointHour = (startHour + endHour) / 2.0
        
        let yAxisStart = midpointHour - 12.0
        let yAxisEnd = midpointHour + 12.0

        return yAxisStart...yAxisEnd
    }

    // Convert Date to decimal hour, respecting the local timezone
    private func getHourFromDate(_ date: Date) -> Double {
        let calendar = Calendar.current // Use the system's local calendar
        let components = calendar.dateComponents(in: calendar.timeZone, from: date)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        return hour + (minute / 60.0)
    }

    // Normalizes an hour by subtracting the y-axis start hour.
    private func normalizeHour(_ hour: Double, relativeTo yAxisStartHour: Double) -> Double {
        var normalized = hour - yAxisStartHour
        // Use fmod to wrap the hour into the 0-24 range, which handles all cases,
        // including sessions that start after midnight.
        normalized = fmod(normalized, 24.0)
        if normalized < 0 {
            normalized += 24.0
        }
        return normalized
    }

    // Format time for Y-axis labels using local timezone
    private func formatTimeForAxis(_ hour: Double) -> String {
        let calendar = Calendar.current
        let yAxisStartHour = yAxisRange.lowerBound
        let actualHour = yAxisStartHour + hour
        
        // Create a reference date (e.g., today) and add the calculated hours
        guard let startOfDay = calendar.startOfDay(for: Date()) as Date? else {
            return ""
        }
        let date = startOfDay.addingTimeInterval(actualHour * 3600)
        
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h a" // e.g., "8 PM"
        
        return formatter.string(from: date)
    }

    // Calculate average bedtime and wake time
    private var averageBedtime: Double {
        guard !sessionsWithData.isEmpty else { return 22.0 } // Default 10 PM
        
        let totalBedtime = sessionsWithData.reduce(0) { total, session in
            guard let startHour = session.originalStartHour else { return total }
            // Normalize to a 0-24 scale where times past midnight are > 24
            let adjustedHour = startHour.truncatingRemainder(dividingBy: 24)
            return total + (adjustedHour < 12 ? adjustedHour + 24 : adjustedHour)
        }
        
        return (totalBedtime / Double(sessionsWithData.count)).truncatingRemainder(dividingBy: 24)
    }

    private var averageWakeTime: Double {
        guard !sessionsWithData.isEmpty else { return 7.0 } // Default 7 AM
        
        let totalWakeTime = sessionsWithData.reduce(0) { total, session in
            guard let endHour = session.originalEndHour else { return total }
            return total + endHour
        }
        
        return (totalWakeTime / Double(sessionsWithData.count)).truncatingRemainder(dividingBy: 24)
    }

    // Calculate average time in bed hours
    private var averageTimeInBedHours: Double {
        guard !sessionsWithData.isEmpty else { return 0 }
        
        let totalTimeInBed = sessionsWithData.reduce(0) { total, session in
            guard let startHour = session.originalStartHour, let endHour = session.originalEndHour else { return total }
            return total + (endHour - startHour)
        }
        
        return totalTimeInBed / Double(sessionsWithData.count)
    }

    private var chartDateInterval: DateInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate: Date
        switch selectedTimeRange {
        case .week, .month:
            startDate = calendar.date(byAdding: .day, value: -(numberOfDays - 1), to: today)!
        case .sixMonths:
            // For 6 months, we go back 6 full months for a more natural interval
            startDate = calendar.date(byAdding: .month, value: -6, to: today)!
        }
        // The end date is tomorrow to ensure the last day is fully included in the range.
        let endDate = calendar.date(byAdding: .day, value: 1, to: today)!
        return DateInterval(start: startDate, end: endDate)
    }

    var body: some View {
        ChartCardView {
            VStack(alignment: .leading, spacing: 12) {
                // Header with time range selector and info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sleep Schedule")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            showInfo.toggle()
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .font(.title3)
                        }
                    }
                    
                    // Time Range Selector
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(ChartTimeRange.allCases, id: \.self) { timeRange in
                            Text(timeRange.rawValue).tag(timeRange)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Info Section (collapsible)
                    if showInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About Sleep Schedule")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Blue blocks show your sleep window from bedtime to wake time")
                                Text("• Regular sleep timing improves sleep quality and daytime alertness")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Average display
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Time in Bed: \(String(format: "%.1f", averageTimeInBedHours))h")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showInfo)
                
                if sleepSessions.isEmpty {
                    Text("No sleep data available for this period.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Chart(sleepSessions) { session in
                        ForEach(session.blocks) { block in
                            BarMark(
                                x: .value("Date", session.date, unit: .day),
                                yStart: .value("Bedtime", block.startHour),
                                yEnd: .value("Wake Time", block.endHour),
                                width: .ratio(0.6)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .foregroundStyle(Color.blue.gradient)
                        }
                    }
                    .chartXAxis {
                        switch selectedTimeRange {
                        case .week:
                            AxisMarks(values: .automatic(desiredCount: 7)) {
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                            }
                        case .month:
                            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day(), centered: true)
                            }
                        case .sixMonths:
                            AxisMarks(values: .stride(by: .month, count: 1)) { value in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 12)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let hour = value.as(Double.self) {
                                    Text(formatTimeForAxis(hour))
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0...24) // Y-axis is now a fixed 0-24 hour window
                    .chartXScale(domain: chartDateInterval.start...chartDateInterval.end)
                    .frame(height: 300)
                }
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = NightlySleepViewModel(context: context)
    
    // Add some sample data
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    
    for i in 0..<30 {
        if let date = calendar.date(byAdding: .day, value: -(29-i), to: today) {
            let session = SleepSessionV2(context: context)
            session.ownershipDay = date
            // Sample bedtime around 10-11 PM
            let bedtimeHour = 22 + Double.random(in: -1...1)
            let bedtimeMinute = Double.random(in: 0...59)
            if let bedtime = calendar.date(bySettingHour: Int(bedtimeHour), minute: Int(bedtimeMinute), second: 0, of: date) {
                session.startDateUTC = bedtime
            }
            // Sample wake time around 6-8 AM next day
            let wakeHour = 7 + Double.random(in: -1...1)
            let wakeMinute = Double.random(in: 0...59)
            if let prevDay = calendar.date(byAdding: .day, value: -1, to: date), let nextDay = calendar.date(byAdding: .day, value: 1, to: date) {
                let wakeDate = bedtimeHour > 12 ? nextDay : date
                if let wakeTime = calendar.date(bySettingHour: Int(wakeHour), minute: Int(wakeMinute), second: 0, of: wakeDate) {
                    session.endDateUTC = wakeTime
                }
            }
            let key = viewModel.cacheKey(for: date)
            viewModel.sleepSessions[key] = session
        }
    }
    
    return SleepScheduleChartView()
        .environmentObject(viewModel)
        .padding()
}
