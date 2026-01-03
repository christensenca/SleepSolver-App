import SwiftUI
import Charts
import Foundation

struct HeartRateChartView: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    @State private var selectedTimeRange: ChartTimeRange = .week
    @State private var showInfo: Bool = false
    
    // Struct to hold heart rate data for each time period
    struct HeartRateData: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let daysSinceStart: Double
        let heartRate: Double? // Average heart rate (bpm), nil if no data
    }
     // Number of days to show in the chart based on selected time range
    private var numberOfDays: Int {
        return selectedTimeRange.dateRange().numberOfDays
    }

    // Compute heart rate data from view model
    private var heartRateData: [HeartRateData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var allData: [HeartRateData] = []
        
        if selectedTimeRange == .sixMonths {
            // For 6-month view, create weekly averages (26 weeks)
            let numberOfWeeks = 26
            for weekIndex in 0..<numberOfWeeks {
                let weekStartDate = calendar.date(byAdding: .day, value: -(numberOfWeeks - 1 - weekIndex) * 7, to: today) ?? today
                
                var weeklyHeartRates: [Double] = []
                
                // Collect data for each day of the week
                for dayOffset in 0..<7 {
                    if let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStartDate) {
                        let key = viewModel.cacheKey(for: date)
                        let session = viewModel.sleepSessions[key]
                        if let unwrappedSession = session, let actualSession = unwrappedSession {
                            if actualSession.averageHeartRate > 0 {
                                weeklyHeartRates.append(actualSession.averageHeartRate)
                            }
                        }
                    }
                }
                
                let avgHeartRate = weeklyHeartRates.isEmpty ? nil : weeklyHeartRates.reduce(0, +) / Double(weeklyHeartRates.count)
                let dayLabel = dateFormatter.string(from: weekStartDate)
                
                allData.append(HeartRateData(
                    date: weekStartDate,
                    dayLabel: dayLabel,
                    daysSinceStart: Double(weekIndex),
                    heartRate: avgHeartRate
                ))
            }
        } else {
            // For week and month views, use daily data
            for i in 0..<numberOfDays {
                if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - i), to: today) {
                    let key = viewModel.cacheKey(for: date)
                    let session = viewModel.sleepSessions[key]
                    let dayLabel = dateFormatter.string(from: date)
                    let daysSinceStart = Double(i)
                    
                    if let unwrappedSession = session, let actualSession = unwrappedSession {
                        allData.append(HeartRateData(
                            date: date,
                            dayLabel: dayLabel,
                            daysSinceStart: daysSinceStart,
                            heartRate: actualSession.averageHeartRate > 0 ? actualSession.averageHeartRate : nil
                        ))
                    } else {
                        allData.append(HeartRateData(
                            date: date,
                            dayLabel: dayLabel,
                            daysSinceStart: daysSinceStart,
                            heartRate: nil
                        ))
                    }
                }
            }
        }
        
        return allData.sorted { $0.date < $1.date }
    }
    
    // Get data with valid heart rate values only (for calculating averages and Y-axis domains)
    private var heartRateDataWithValues: [HeartRateData] {
        return heartRateData.filter { $0.heartRate != nil }
    }
    
    // Date formatter for labels
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        switch selectedTimeRange {
        case .week:
            formatter.dateFormat = "EEE" // e.g., "Mon"
        case .month:
            formatter.dateFormat = "MMM d" // e.g., "Jan 15"
        case .sixMonths:
            formatter.dateFormat = "MMM d" // e.g., "Jan 1" (week start dates)
        }
        return formatter
    }
    
private var sixMonthAxisData: (values: [Double], labels: [String]) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let startDate = calendar.date(byAdding: .day, value: -175, to: today)! // 25 weeks ago
    let endDate = today

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM"

    // Arrays to hold x-axis values and labels
    var axisValues: [Double] = [0] // Start at x = 0
    var axisLabels: [String] = [formatter.string(from: startDate)] // Label for start month

    // Start from the next month after startDate's month
    var currentMonthDate = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
    currentMonthDate = calendar.date(byAdding: .month, value: 1, to: currentMonthDate)!

    // Add labels for each month’s first day within the period
    while currentMonthDate < endDate {
        let daysFromStart = calendar.dateComponents([.day], from: startDate, to: currentMonthDate).day!
        let xValue = Double(daysFromStart) / 7.0
        let monthLabel = formatter.string(from: currentMonthDate)
        axisValues.append(xValue)
        axisLabels.append(monthLabel)
        currentMonthDate = calendar.date(byAdding: .month, value: 1, to: currentMonthDate)!
    }

    // Add the end month label at x = 25 if not already included
    let endMonthLabel = formatter.string(from: endDate)
    if !axisLabels.contains(endMonthLabel) {
        axisValues.append(25)
        axisLabels.append(endMonthLabel)
    }

    return (values: axisValues, labels: axisLabels)
}
    
    // Custom X-axis values
    private var customXAxisValues: [Double] {
        switch selectedTimeRange {
        case .week:
            return Array(0..<7).map { Double($0) } // Show all 7 days
        case .month:
            return stride(from: 0, to: numberOfDays, by: 5).map { Double($0) } // Every 5 days
        case .sixMonths:
            return sixMonthAxisData.values
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
            return sixMonthAxisData.labels
        }
    }
    
    // Calculate average heart rate
    private var averageHeartRate: Double {
        guard !heartRateDataWithValues.isEmpty else { return 0 }
        let total = heartRateDataWithValues.compactMap { $0.heartRate }.reduce(0, +)
        return total / Double(heartRateDataWithValues.count)
    }
    
    // Adjusted Y-axis domain with more padding and lower minimum
    private var heartRateYDomain: ClosedRange<Double> {
        guard !heartRateDataWithValues.isEmpty else { return 20...100 }
        let heartRates = heartRateDataWithValues.compactMap { $0.heartRate }
        guard !heartRates.isEmpty else { return 20...100 }
        let minHR = heartRates.min() ?? 20.0
        let maxHR = heartRates.max() ?? 100.0
        
        // Lower bound: round down to nearest 10, subtract 10, ensure at least 20
        let lowerBound = max(20.0, floor(minHR / 10.0) * 10.0 - 10.0)
        
        // Upper bound: round up to nearest 10, add 10
        let upperBound = ceil(maxHR / 10.0) * 10.0 + 10.0
        
        return lowerBound...upperBound
    }
    
    // Computed property for xDomain with padding to prevent leftmost bar overlap
    private var xDomain: ClosedRange<Double> {
        let minX = heartRateData.map { $0.daysSinceStart }.min() ?? 0
        let maxX: Double
        
        // For 6-month view, max is 25 (26 weeks: 0-25), not numberOfDays
        if selectedTimeRange == .sixMonths {
            maxX = heartRateData.map { $0.daysSinceStart }.max() ?? 25
        } else {
            maxX = heartRateData.map { $0.daysSinceStart }.max() ?? Double(numberOfDays - 1)
        }
        
        let padding: Double = selectedTimeRange == .sixMonths ? 0.5 : 0.8 // Smaller padding for 6-month view
        return (minX - padding)...(maxX + padding)
    }
    
    // Split data into segments of consecutive non-nil heart rate values
    private var dataSegments: [[HeartRateData]] {
        var segments: [[HeartRateData]] = []
        var currentSegment: [HeartRateData] = []
        
        for item in heartRateData {
            if item.heartRate != nil {
                currentSegment.append(item)
            } else {
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                    currentSegment = []
                }
            }
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }
        return segments
    }
    
    // Adjusted symbol size
    private var symbolSize: CGFloat {
        switch selectedTimeRange {
        case .week:
            return 50 // Larger for fewer points
        case .month:
            return 30
        case .sixMonths:
            return 20 // Smaller for more points
        }
    }
    
    var body: some View {
        ChartCardView {
            VStack(alignment: .leading, spacing: 12) {
                // Header with time range selector and info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Heart Rate")
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
                    .onChange(of: selectedTimeRange) { _, _ in
                        // No data fetching logic here
                    }
                    
                    // Info Section (collapsible)
                    if showInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About Heart Rate During Sleep")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Lower heart rate during sleep indicates good recovery")
                                Text("• Consistently high values may indicate stress or poor recovery")
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
                    if !heartRateDataWithValues.isEmpty {
                        Text("Avg: \(String(format: "%.0f", averageHeartRate)) bpm")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showInfo)
                
                if heartRateDataWithValues.isEmpty {
                    Text("No heart rate data available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        // Plot each segment as a separate LineMark with symbols
                        ForEach(dataSegments.indices, id: \.self) { segmentIndex in
                            let segment = dataSegments[segmentIndex]
                            ForEach(segment) { item in
                                if let heartRate = item.heartRate {
                                    LineMark(
                                        x: .value("Day", item.daysSinceStart),
                                        y: .value("Heart Rate", heartRate)
                                    )
                                    .foregroundStyle(.red)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                    
                                    PointMark(
                                        x: .value("Day", item.daysSinceStart),
                                        y: .value("Heart Rate", heartRate)
                                    )
                                    .foregroundStyle(.red)
                                    .symbolSize(symbolSize) // Adjusted
                                }
                            }
                        }
                        
                        // Average line
                        if averageHeartRate > 0 {
                            RuleMark(
                                y: .value("Average", averageHeartRate)
                            )
                            .foregroundStyle(.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        }
                    }
                    .frame(height: 200)
                    .animation(.easeInOut(duration: 0.3), value: selectedTimeRange)
                    .chartYScale(domain: heartRateYDomain)
                    .chartXScale(domain: xDomain)
                    .chartXAxis {
                        AxisMarks(values: customXAxisValues) { value in
                            if let doubleValue = value.as(Double.self),
                               let labelIndex = customXAxisValues.firstIndex(of: doubleValue),
                               labelIndex < customXAxisLabels.count {
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel {
                                    Text(customXAxisLabels[labelIndex])
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let heartRate = value.as(Double.self) {
                                    Text("\(Int(heartRate))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // No data fetching logic here
        }
    }
}
