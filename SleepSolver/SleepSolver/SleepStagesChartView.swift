import SwiftUI
import Charts
import Foundation

struct SleepStagesChartView: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    @State private var selectedTimeRange: ChartTimeRange = .week
    @State private var showInfo: Bool = false
    
    // Struct to hold sleep stage data for each day
    struct SleepStageData: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let daysSinceStart: Double
        let stage: String
        let duration: Double // in hours
    }
    
    // Number of days to show in the chart based on selected time range
    private var numberOfDays: Int {
        return selectedTimeRange.dateRange().numberOfDays
    }
    
    // Compute sleep stages data from view model
    private var sleepStagesData: [SleepStageData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var allData: [SleepStageData] = []
        
        // Generate all daily data points for the time range
        for i in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - i), to: today) {
                let key = viewModel.cacheKey(for: date)
                let session = viewModel.sleepSessions[key]
                let dayLabel = dateFormatter.string(from: date)
                let daysSinceStart = Double(i)
                
                if let unwrappedSession = session, let actualSession = unwrappedSession {
                    // Add REM sleep data
                    let remHours = actualSession.remDuration / 3600.0
                    allData.append(SleepStageData(
                        date: date,
                        dayLabel: dayLabel,
                        daysSinceStart: daysSinceStart,
                        stage: "REM",
                        duration: remHours
                    ))
                    
                    // Add Deep sleep data
                    let deepHours = actualSession.deepDuration / 3600.0
                    allData.append(SleepStageData(
                        date: date,
                        dayLabel: dayLabel,
                        daysSinceStart: daysSinceStart,
                        stage: "Deep",
                        duration: deepHours
                    ))
                } else {
                    // Add data points with 0 duration for missing data
                    allData.append(SleepStageData(
                        date: date,
                        dayLabel: dayLabel,
                        daysSinceStart: daysSinceStart,
                        stage: "REM",
                        duration: 0
                    ))
                    allData.append(SleepStageData(
                        date: date,
                        dayLabel: dayLabel,
                        daysSinceStart: daysSinceStart,
                        stage: "Deep",
                        duration: 0
                    ))
                }
            }
        }
        
        // For 6-month view, use intelligent sampling to pick representative days
        if selectedTimeRange == .sixMonths {
            let windowSize = 4
            var sampledData: [SleepStageData] = []
            
            // Group data into windows of 4 days (each day has 2 entries: REM and Deep)
            let dailyGroups = Dictionary(grouping: allData, by: { $0.date })
            let sortedDates = Array(dailyGroups.keys).sorted()
            
            // Process windows of 4 days
            for windowStart in stride(from: 0, to: sortedDates.count, by: windowSize) {
                let windowEnd = min(windowStart + windowSize, sortedDates.count)
                let windowDates = Array(sortedDates[windowStart..<windowEnd])
                
                // Find dates with complete data in this window (both REM and Deep > 0)
                let datesWithData = windowDates.filter { date in
                    guard let dayData = dailyGroups[date] else { return false }
                    return dayData.allSatisfy { $0.duration > 0 }
                }
                
                if !datesWithData.isEmpty {
                    // Pick the date closest to the middle of the window (best representative day)
                    let targetIndex = windowDates.count / 2
                    let bestDate = datesWithData.min { date1, date2 in
                        let index1 = windowDates.firstIndex(of: date1) ?? 0
                        let index2 = windowDates.firstIndex(of: date2) ?? 0
                        return abs(index1 - targetIndex) < abs(index2 - targetIndex)
                    }
                    if let selectedDate = bestDate, let selectedData = dailyGroups[selectedDate] {
                        sampledData.append(contentsOf: selectedData)
                    }
                } else {
                    // No complete data in this window, pick the first available day to maintain timeline continuity
                    if let firstDate = windowDates.first, let firstData = dailyGroups[firstDate] {
                        sampledData.append(contentsOf: firstData)
                    }
                }
            }
            
            return sampledData.sorted { $0.date < $1.date }
        }
        
        return allData.sorted { $0.date < $1.date }
    }
    
    // Date formatter for day labels
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        switch selectedTimeRange {
        case .week:
            formatter.dateFormat = "EEE" // e.g., "Mon"
        case .month:
            formatter.dateFormat = "MMM d" // e.g., "Jan 15"
        case .sixMonths:
            formatter.dateFormat = "MMM" // e.g., "Jan"
        }
        return formatter
    }
    
    // Custom X-axis values and labels for different time ranges
    private var customXAxisValues: [Double] {
        switch selectedTimeRange {
        case .week:
            return Array(0..<7).map { Double($0) } // Show all 7 days
        case .month:
            return stride(from: 0, to: numberOfDays, by: 5).map { Double($0) } // Every 5 days
        case .sixMonths:
            return stride(from: 0, to: numberOfDays, by: 30).map { Double($0) } // Monthly intervals
        }
    }
    
    // Custom X-axis labels
    private var customXAxisLabels: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        switch selectedTimeRange {
        case .week:
            // Show day names: Mon, Tue, Wed, etc.
            return customXAxisValues.compactMap { dayIndex in
                if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - Int(dayIndex)), to: today) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEE"
                    return formatter.string(from: date)
                }
                return nil
            }
        case .month:
            // Show calendar dates: 5, 10, 15, etc.
            return customXAxisValues.compactMap { dayIndex in
                if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - Int(dayIndex)), to: today) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "d"
                    return formatter.string(from: date)
                }
                return nil
            }
        case .sixMonths:
            // Show month names: April, May, June, etc.
            return customXAxisValues.compactMap { dayIndex in
                if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - Int(dayIndex)), to: today) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM"
                    return formatter.string(from: date)
                }
                return nil
            }
        }
    }
    
    // Calculate average restorative sleep (REM + Deep)
    private var averageRestorativeSleep: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totalHours: Double = 0
        var daysWithData = 0
        
        for i in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - i), to: today) {
                let key = viewModel.cacheKey(for: date)
                let session = viewModel.sleepSessions[key]
                
                if let unwrappedSession = session, let actualSession = unwrappedSession {
                    let remHours = actualSession.remDuration / 3600.0
                    let deepHours = actualSession.deepDuration / 3600.0
                    totalHours += (remHours + deepHours)
                    daysWithData += 1
                }
            }
        }
        
        return daysWithData > 0 ? totalHours / Double(daysWithData) : 0
    }
    
    // Calculate Y-axis range based on data
    private var yAxisRange: ClosedRange<Double> {
        guard !sleepStagesData.isEmpty else {
            return 0...4 // Default range
        }
        
        // Group by date and sum REM + Deep for each day
        let dailySums = Dictionary(grouping: sleepStagesData, by: { $0.date })
            .mapValues { stages in
                stages.reduce(0) { $0 + $1.duration }
            }
        
        let allValues = Array(dailySums.values)
        let maxValue = allValues.max() ?? 4
        
        // Add some padding for visual clarity
        let padding = max(0.5, maxValue * 0.1)
        let maxRange = maxValue + padding
        
        return 0...maxRange
    }

    // Computed property for xDomain with padding to prevent leftmost bar overlap
    private var xDomain: ClosedRange<Double> {
        let minX = sleepStagesData.map { $0.daysSinceStart }.min() ?? 0
        let maxX = sleepStagesData.map { $0.daysSinceStart }.max() ?? Double(numberOfDays - 1)
        let padding: Double = 0.8 // Adjust padding as needed to prevent Y-axis overlap
        return (minX - padding)...(maxX + padding)
    }

    var body: some View {
        ChartCardView {
            VStack(alignment: .leading, spacing: 12) {
                // Header with time range selector and info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Restorative Sleep")
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
                            Text("About Restorative Sleep")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• REM sleep supports memory consolidation and emotional processing")
                                Text("• Deep sleep is crucial for physical recovery and immune function")
                                Text("• Adults typically need 1.5-2h of REM and 1-2h of deep sleep nightly")
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
                    if averageRestorativeSleep > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average: \(String(format: "%.1f", averageRestorativeSleep))h")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showInfo)
                
                if sleepStagesData.isEmpty {
                    Text("No restorative sleep data available")
                        .foregroundColor(.secondary)
                        .frame(height: 250)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        // Stacked bar data
                        ForEach(sleepStagesData) { data in
                            BarMark(
                                x: .value("Days Since Start", data.daysSinceStart),
                                y: .value("Duration", data.duration),
                                width: selectedTimeRange == .week ? 20 : 
                                       selectedTimeRange == .month ? 8 : 4, // Responsive bar width
                                stacking: .standard
                            )
                            .foregroundStyle(by: .value("Stage", data.stage))
                        }
                        
                        // Average line
                        if averageRestorativeSleep > 0 {
                            RuleMark(y: .value("Average", averageRestorativeSleep))
                                .foregroundStyle(Color.orange.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        }
                    }
                    .chartForegroundStyleScale([
                        "REM": LinearGradient(colors: [Color.purple.opacity(0.8), Color.purple], startPoint: .bottom, endPoint: .top),
                        "Deep": LinearGradient(colors: [Color.blue.opacity(0.8), Color.blue], startPoint: .bottom, endPoint: .top)
                    ])
                    .chartXAxis {
                        AxisMarks(values: customXAxisValues) { value in
                            if let dayIndex = value.as(Double.self),
                               let labelIndex = customXAxisValues.firstIndex(of: dayIndex),
                               labelIndex < customXAxisLabels.count {
                                AxisValueLabel {
                                    Text(customXAxisLabels[labelIndex])
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                AxisTick()
                                AxisGridLine()
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let hours = value.as(Double.self) {
                                    Text("\(String(format: "%.1f", hours))h")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            AxisTick()
                            AxisGridLine()
                        }
                    }
                    .chartXScale(domain: xDomain) // Set the extended domain with padding
                    .chartYScale(domain: yAxisRange)
                    .frame(height: 250)
                    .animation(.easeInOut(duration: 0.3), value: selectedTimeRange)
                }
            }
        }
    }
}

struct SleepStagesChartView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let viewModel = NightlySleepViewModel(context: context)
        
        // Add sample data for testing different time ranges
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Generate 60 days of sample sleep data with some gaps
        for i in 0..<60 {
            if let date = calendar.date(byAdding: .day, value: -(60 - 1 - i), to: today) {
                // Skip some days to create gaps (simulate missing data)
                if i % 7 != 0 && i % 11 != 0 { // Skip every 7th and 11th day
                    let session = SleepSessionV2(context: context)
                    session.ownershipDay = date
                    session.remDuration = Double.random(in: 3600...7200) // 1-2 hours
                    session.deepDuration = Double.random(in: 3600...7200) // 1-2 hours
                    let key = viewModel.cacheKey(for: date)
                    viewModel.sleepSessions[key] = session
                }
            }
        }
        
        return SleepStagesChartView()
            .environmentObject(viewModel)
            .padding()
    }
}
