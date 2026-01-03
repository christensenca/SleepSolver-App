import SwiftUI
import Charts
import Foundation

struct SleepDebtChartView: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    @State private var selectedTimeRange: ChartTimeRange = .week
    @State private var showInfo: Bool = false
    
    // Struct to hold sleep debt data for each day
    struct SleepDebtData: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let daysSinceStart: Double
        let dailyDebt: Double // Daily sleep debt (hours)
    }
    
    // Number of days to show in the chart based on selected time range
    private var numberOfDays: Int {
        return selectedTimeRange.dateRange().numberOfDays
    }
    
    // Get user's sleep need from UserDefaults
    private var userSleepNeed: Double {
        return UserDefaults.standard.double(forKey: "userSleepNeed")
    }
    
    // Compute sleep debt data from view model
    private var sleepDebtData: [SleepDebtData] {
        guard userSleepNeed > 0 else { return [] } // No sleep need set
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var allData: [SleepDebtData] = []
        
        // Calculate daily sleep debt values
        for i in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: -(numberOfDays - 1 - i), to: today) {
                let key = viewModel.cacheKey(for: date)
                let session = viewModel.sleepSessions[key]
                
                let dailyDebt: Double
                if let unwrappedSession = session, let actualSession = unwrappedSession {
                    let actualSleepHours = actualSession.totalSleepTime / 3600.0 // Convert seconds to hours
                    dailyDebt = userSleepNeed - actualSleepHours // Raw deficit/surplus, no caps
                } else {
                    dailyDebt = 0 // No data, no debt change
                }
                
                let dayLabel = dateFormatter.string(from: date)
                let daysSinceStart = Double(i)
                
                allData.append(SleepDebtData(
                    date: date,
                    dayLabel: dayLabel,
                    daysSinceStart: daysSinceStart,
                    dailyDebt: dailyDebt
                ))
            }
        }
        
        // For 6-month view, use intelligent sampling to pick representative days
        if selectedTimeRange == .sixMonths {
            let windowSize = 4
            var sampledData: [SleepDebtData] = []
            
            // Group data into windows of 4 days
            for windowStart in stride(from: 0, to: allData.count, by: windowSize) {
                let windowEnd = min(windowStart + windowSize, allData.count)
                let window = Array(allData[windowStart..<windowEnd])
                
                // Find sessions with actual sleep data in this window (non-zero debt change)
                let dataWithSleep = window.filter { debtData in
                    let key = viewModel.cacheKey(for: debtData.date)
                    return viewModel.sleepSessions[key] != nil
                }
                
                if !dataWithSleep.isEmpty {
                    // Pick the session closest to the middle of the window (best representative day)
                    let targetIndex = window.count / 2
                    let bestData = dataWithSleep.min { data1, data2 in
                        let index1 = window.firstIndex { $0.id == data1.id } ?? 0
                        let index2 = window.firstIndex { $0.id == data2.id } ?? 0
                        return abs(index1 - targetIndex) < abs(index2 - targetIndex)
                    }
                    if let selected = bestData {
                        sampledData.append(selected)
                    }
                } else {
                    // No sleep data in this window, pick the first day to maintain timeline continuity
                    sampledData.append(window[0])
                }
            }
            
            return sampledData
        }
        
        return allData
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
    
    // Group data into segments of consecutive days with sleep data
    private var dataSegments: [[SleepDebtData]] {
        var segments: [[SleepDebtData]] = []
        var currentSegment: [SleepDebtData] = []
        
        for data in sleepDebtData {
            let key = viewModel.cacheKey(for: data.date)
            if viewModel.sleepSessions[key] != nil { // Check if data exists
                currentSegment.append(data)
            } else if !currentSegment.isEmpty {
                segments.append(currentSegment)
                currentSegment = []
            }
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }
        return segments
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
    
    // Y-axis range based on daily debt values
    private var yAxisRange: ClosedRange<Double> {
        guard !sleepDebtData.isEmpty else {
            return -2...2 // Default range
        }
        
        let allValues = sleepDebtData.map { $0.dailyDebt }
        let minValue = allValues.min() ?? 0
        let maxValue = allValues.max() ?? 0
        
        // Add some padding for visual clarity
        let padding = max(0.5, abs(maxValue - minValue) * 0.1)
        let minRange = minValue - padding
        let maxRange = maxValue + padding
        
        return minRange...maxRange
    }
    
    // Format hours for Y-axis labels
    private func formatHours(_ hours: Double) -> String {
        let absHours = abs(hours)
        let sign = hours >= 0 ? "+" : "-"
        return String(format: "%@%.1fh", sign, absHours)
    }
    
    // Current sleep debt (last value in the series)
    private var currentSleepDebt: Double {
        return sleepDebtData.last?.dailyDebt ?? 0
    }
    
    // Computed property for xDomain with padding to prevent label cutoff
    private var xDomain: ClosedRange<Double> {
        let minX = sleepDebtData.map { $0.daysSinceStart }.min() ?? 0
        let maxX: Double
        
        // For 6-month view, max is based on actual data, not numberOfDays
        if selectedTimeRange == .sixMonths {
            maxX = sleepDebtData.map { $0.daysSinceStart }.max() ?? Double(numberOfDays - 1)
        } else {
            maxX = sleepDebtData.map { $0.daysSinceStart }.max() ?? Double(numberOfDays - 1)
        }
        
        let padding: Double = selectedTimeRange == .sixMonths ? 0.5 : 0.8 // Smaller padding for 6-month view
        return (minX - padding)...(maxX + padding)
    }

    var body: some View {
        ChartCardView {
            VStack(alignment: .leading, spacing: 12) {
                // Header with time range selector and info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sleep Debt")
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
                            Text("About Sleep Debt")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Sleep debt shows daily sleep deficits and surpluses")
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
                    
                    if userSleepNeed <= 0 {
                        Text("Set your sleep need in settings to view sleep debt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Debt: \(formatHours(currentSleepDebt))")
                                .font(.caption)
                                .foregroundColor(currentSleepDebt > 0 ? .red : .green)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showInfo)
                
                if sleepDebtData.isEmpty || userSleepNeed <= 0 {
                    Text("No sleep debt data available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        // Plot each segment as a separate line to handle gaps in data
                        ForEach(dataSegments, id: \.first?.id) { segment in
                            ForEach(segment) { data in
                                LineMark(
                                    x: .value("Days Since Start", data.daysSinceStart),
                                    y: .value("Daily Debt", data.dailyDebt)
                                )
                                .foregroundStyle(Color.red.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 3))
                                .symbol(.circle)
                                .symbolSize(selectedTimeRange == .week ? 50 : 30) // Smaller symbols for longer periods
                            }
                        }
                        
                       
                        RuleMark(y: .value("Zero Debt", 0))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
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
                                if let debtValue = value.as(Double.self) {
                                    Text(formatHours(debtValue))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            AxisTick()
                            AxisGridLine()
                        }
                    }
                    .chartXScale(domain: xDomain) // Set the extended domain with padding
                    .frame(height: 250)
                    .animation(.easeInOut(duration: 0.3), value: selectedTimeRange)
                }
            }
        }
        .onAppear {
            // Removed data fetching logic
        }
        .onChange(of: selectedTimeRange) { _, _ in
            // Removed data fetching logic
        }
    }
}

private extension SleepDebtChartView {
    static func makePreviewViewModel() -> NightlySleepViewModel {
        let context = PersistenceController.preview.container.viewContext
        let viewModel = NightlySleepViewModel(context: context)
        UserDefaults.standard.set(8.0, forKey: "userSleepNeed")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for i in 0..<60 {
            if let date = calendar.date(byAdding: .day, value: -(60 - 1 - i), to: today) {
                if i % 7 != 0 && i % 11 != 0 {
                    let session = SleepSessionV2(context: context)
                    session.ownershipDay = date
                    let baseSleep = 7.5
                    let variation = Double.random(in: -1.5...1.5)
                    session.totalSleepTime = (baseSleep + variation) * 3600
                    let key = viewModel.cacheKey(for: date)
                    viewModel.sleepSessions[key] = session
                }
            }
        }
        return viewModel
    }
}

#Preview {
    SleepDebtChartView()
        .environmentObject(SleepDebtChartView.makePreviewViewModel())
        .padding()
}
