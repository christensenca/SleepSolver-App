import SwiftUI
import CoreData
import HealthKit

// MARK: - Heart Rate Data Structure
struct HeartRateDataPoint {
    let date: Date
    let heartRate: Double
}

// Conform to DateProviderView
struct DailyHabitsView: View, DateProviderView {
    let date: Date
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: DailyHabitsViewModel
    let reloadTrigger: UUID // ADDED: To trigger reloads
    
    // Bedtime setting from UserDefaults
    @AppStorage("userBedtime") private var userBedtime: Double = 21.0 // 9 PM in 24-hour format

    // State for delete confirmation
    @State private var showingDeleteConfirmation = false
    @State private var habitToDelete: ManualHabitDisplayItem? = nil
    
    // Heart rate monitoring state
    @State private var heartRateData: [HeartRateDataPoint] = []
    @State private var isLoadingHeartRate = false
    @State private var heartRateBaseline: Double? = nil
    @State private var currentDeviation: Double? = nil
    @State private var heartRateStartTime: Date? = nil
    @State private var heartRateEndTime: Date? = nil


    // Computes the main title (e.g., "Today", "Tuesday")
    private var title: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Full name of the day of the week
            return formatter.string(from: date)
        }
    }

    // Computes the subtitle (e.g., "May 3")
    private var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // e.g., May 3
        return formatter.string(from: date)
    }
    
    // Check if we should show pre-bedtime heart rate section
    private var shouldShowPreBedtimeSection: Bool {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            // For today: Show if we're within 1 hour of bedtime (same logic as before)
            let now = Date()
            let bedtimeHour = Int(userBedtime)
            let bedtimeMinute = Int((userBedtime - Double(bedtimeHour)) * 60)
            
            guard let todayBedtime = calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: now),
                  let oneHourBeforeBedtime = calendar.date(byAdding: .hour, value: -1, to: todayBedtime) else {
                return false
            }
            
            // Show section if current time is at or after the start time (1 hour before bedtime)
            return now >= oneHourBeforeBedtime
        } else {
            // For previous days: Show if there's a sleep session with startDateUTC
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
                return false
            }
            
            let session = viewModel.getSleepSession(for: nextDay)
            return session != nil
        }
    }


    // Initializer now just sets the date, ViewModel is initialized via @StateObject
    init(date: Date, context: NSManagedObjectContext, nightlySleepViewModel: NightlySleepViewModel, reloadTrigger: UUID) { // MODIFIED: Added nightlySleepViewModel and reloadTrigger
        self.date = date
        self._viewModel = StateObject(wrappedValue: DailyHabitsViewModel(context: context, nightlySleepViewModel: nightlySleepViewModel))
        self.reloadTrigger = reloadTrigger // ADDED: Initialize reloadTrigger
    }


    var body: some View {
        List {
            // Loading state
            if viewModel.isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowSeparator(.hidden)
            } else if let errorMessage = viewModel.errorMessage {
                Section {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowSeparator(.hidden)
            } else {
                // Pre-Bedtime Heart Rate Monitoring (Today and Previous Days with Sleep Sessions)
                if shouldShowPreBedtimeSection {
                    Section {
                        PreBedtimeHeartRateCard(
                            heartRateData: heartRateData,
                            baseline: heartRateBaseline,
                            deviation: currentDeviation,
                            isLoading: isLoadingHeartRate,
                            bedtime: userBedtime,
                            date: date,
                            startTime: heartRateStartTime,
                            endTime: heartRateEndTime
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15))
                    }
                    .listRowSeparator(.hidden)
                }
                
                // Activity Summary Section (HealthKit metrics)
                if !viewModel.healthKitItems.isEmpty {
                    Section(header: Text("Activity Summary")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 0)
                    ) {
                        ForEach(viewModel.healthKitItems) { item in
                            HealthKitDisplayCard(item: item)
                                .listRowInsets(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15))
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                
                // Workouts Section
                if !viewModel.workoutItems.isEmpty {
                    Section(header: Text("Workouts")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 0)
                    ) {
                        ForEach(viewModel.workoutItems) { workout in
                            WorkoutDisplayCard(workout: workout)
                                .listRowInsets(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15))
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                
                // Manual Habits Section
                if !viewModel.manualHabitItems.isEmpty {
                    Section(header: Text("Habits")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 0)
                    ) {
                        ForEach(viewModel.manualHabitItems) { item in
                            ManualHabitDisplayCard(item: item)
                                .listRowInsets(EdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15))
                                .onLongPressGesture {
                                    habitToDelete = item
                                    showingDeleteConfirmation = true
                                }
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                
                // Empty state only if no data at all
                if viewModel.healthKitItems.isEmpty && viewModel.workoutItems.isEmpty && viewModel.manualHabitItems.isEmpty {
                    Section {
                        Text("No activity or habits logged for this day.")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .animation(.easeInOut(duration: 1.0), value: viewModel.healthKitItems.count + viewModel.manualHabitItems.count + viewModel.workoutItems.count) // MODIFIED: Make animation slower
        .animation(.easeInOut(duration: 1.0), value: viewModel.workoutItems) // ADDED: Animation for workouts
        .id(reloadTrigger) // ADDED: Force List to reconstruct when reloadTrigger changes
        .listStyle(.plain)
        .actionSheet(isPresented: $showingDeleteConfirmation) {
            ActionSheet(
                title: Text("Delete Habit?"),
                message: Text("Are you sure you want to delete the record for \"\(habitToDelete?.name ?? "this habit")\""),
                buttons: [
                    .destructive(Text("Delete")) {
                        if let habit = habitToDelete {
                            viewModel.removeHabitRecord(habitName: habit.name, date: date)
                            habitToDelete = nil // Reset after action
                        }
                    },
                    .cancel { // "Keep" is implied by Cancel
                         habitToDelete = nil // Reset on cancel
                    }
                ]
            )
        }
        .onChange(of: reloadTrigger) { _, _ in
            viewModel.loadData(for: date)
        }
        .onAppear {
            viewModel.loadData(for: date)
            
            // Load heart rate data if pre-bedtime section should be shown
            if shouldShowPreBedtimeSection {
                loadPreBedtimeHeartRate()
            }
        }
        .onChange(of: shouldShowPreBedtimeSection) { _, newValue in
            if newValue {
                loadPreBedtimeHeartRate()
            }
        }
    }
    
    // MARK: - Heart Rate Data Loading
    
    private func loadPreBedtimeHeartRate() {
        guard shouldShowPreBedtimeSection else { return }
        
        print("🫀 Loading pre-bedtime heart rate for date: \(date)")
        isLoadingHeartRate = true
        let calendar = Calendar.current
        
        let queryStartDate: Date
        let queryEndDate: Date
        let displayStartDate: Date
        let displayEndDate: Date
        
        if calendar.isDateInToday(date) {
            print("📅 Loading for TODAY")
            // For today: Use current bedtime calculation
            let now = Date()
            let bedtimeHour = Int(userBedtime)
            let bedtimeMinute = Int((userBedtime - Double(bedtimeHour)) * 60)
            
            guard let todayBedtime = calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: now) else {
                print("❌ Failed to calculate today's bedtime")
                isLoadingHeartRate = false
                return
            }
            
            // Query 80 minutes of data (for 20-minute baseline establishment)
            guard let eightyMinutesBefore = calendar.date(byAdding: .minute, value: -80, to: todayBedtime),
                  let oneHourBefore = calendar.date(byAdding: .hour, value: -1, to: todayBedtime) else {
                print("❌ Failed to calculate today's time ranges")
                isLoadingHeartRate = false
                return
            }
            
            queryStartDate = eightyMinutesBefore  // -80 minutes for data collection
            queryEndDate = todayBedtime           // bedtime
            displayStartDate = oneHourBefore      // -60 minutes for chart display
            displayEndDate = todayBedtime         // bedtime
            
        } else {
            print("📅 Loading for HISTORICAL date")
            // For historical data: Use sleepSessionV2.startDateUTC with 80-minute query window
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)),
                  let session = viewModel.getSleepSession(for: nextDay) else {
                print("❌ Failed to get sleep session for historical date")
                isLoadingHeartRate = false
                return
            }
            
            print("💤 Found sleep session starting at: \(session.startDateUTC)")
            
            // Query 80 minutes of data (for 20-minute baseline establishment)
            guard let eightyMinutesBefore = calendar.date(byAdding: .minute, value: -80, to: session.startDateUTC),
                  let oneHourBefore = calendar.date(byAdding: .hour, value: -1, to: session.startDateUTC) else {
                print("❌ Failed to calculate historical time ranges")
                isLoadingHeartRate = false
                return
            }
            
            queryStartDate = eightyMinutesBefore   // -80 minutes for data collection
            queryEndDate = session.startDateUTC    // sleep session start
            displayStartDate = oneHourBefore       // -60 minutes for chart display
            displayEndDate = session.startDateUTC  // sleep session start
        }
        
        print("🔍 Query window: \(queryStartDate) to \(queryEndDate) (80 minutes)")
        print("📊 Display window: \(displayStartDate) to \(displayEndDate) (60 minutes)")
        
        fetchHeartRateData(from: queryStartDate, to: queryEndDate) { dataPoints in
            DispatchQueue.main.async {
                print("🔍 DATA FILTER DEBUG: Received \(dataPoints.count) total data points")
                if !dataPoints.isEmpty {
                    print("🔍 DATA FILTER DEBUG: First data point: \(dataPoints.first!.heartRate) BPM at \(dataPoints.first!.date)")
                    print("🔍 DATA FILTER DEBUG: Last data point: \(dataPoints.last!.heartRate) BPM at \(dataPoints.last!.date)")
                }
                
                // Filter data to only show points within the display window (1 hour)
                let displayDataPoints = dataPoints.filter { point in
                    point.date >= displayStartDate && point.date <= displayEndDate
                }
                
                print("🔍 DATA FILTER DEBUG: After filtering for display window (\(displayStartDate) to \(displayEndDate)): \(displayDataPoints.count) points")
                if !displayDataPoints.isEmpty {
                    print("🔍 DATA FILTER DEBUG: First display point: \(displayDataPoints.first!.heartRate) BPM at \(displayDataPoints.first!.date)")
                    print("🔍 DATA FILTER DEBUG: Last display point: \(displayDataPoints.last!.heartRate) BPM at \(displayDataPoints.last!.date)")
                }
                
                self.heartRateData = displayDataPoints  // Only show 1-hour window data
                self.heartRateStartTime = displayStartDate  // Chart shows 1-hour window
                self.heartRateEndTime = displayEndDate      // Chart shows 1-hour window
                self.calculateBaselineAndDeviation(allDataPoints: dataPoints, displayDataPoints: displayDataPoints, baselineWindowStart: queryStartDate)
                self.isLoadingHeartRate = false
            }
        }
    }
    
    private func fetchHeartRateData(from startDate: Date, to endDate: Date, completion: @escaping ([HeartRateDataPoint]) -> Void) {
        print("🫀 Fetching heart rate data from \(startDate) to \(endDate)")
        
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            
            if let error = error {
                print("❌ Error fetching heart rate data: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let samples = samples as? [HKQuantitySample] else {
                print("❌ No heart rate samples found")
                completion([])
                return
            }
            
            print("✅ Found \(samples.count) heart rate samples")
            
            let dataPoints = samples.map { sample in
                HeartRateDataPoint(
                    date: sample.startDate,
                    heartRate: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                )
            }
            
            print("📊 Heart rate data points: \(dataPoints.count)")
            if !dataPoints.isEmpty {
                print("📊 First HR: \(dataPoints.first!.heartRate) BPM at \(dataPoints.first!.date)")
                print("📊 Last HR: \(dataPoints.last!.heartRate) BPM at \(dataPoints.last!.date)")
            }
            
            completion(dataPoints)
        }
        
        HKHealthStore().execute(query)
    }
    
    private func calculateBaselineAndDeviation(allDataPoints: [HeartRateDataPoint], displayDataPoints: [HeartRateDataPoint], baselineWindowStart: Date) {
        print("🔍 CALCULATION DEBUG: Starting baseline and deviation calculation")
        print("🔍 CALCULATION DEBUG: All data points: \(allDataPoints.count), Display data points: \(displayDataPoints.count)")
        
        // Always calculate baseline - either from data or default to 60 BPM
        let twentyMinutesAfterStart = Calendar.current.date(byAdding: .minute, value: 20, to: baselineWindowStart) ?? baselineWindowStart
        let baselinePoints = allDataPoints.filter { $0.date >= baselineWindowStart && $0.date <= twentyMinutesAfterStart }
        
        if !baselinePoints.isEmpty {
            let baseline = baselinePoints.map { $0.heartRate }.reduce(0, +) / Double(baselinePoints.count)
            heartRateBaseline = baseline
            print("📊 Baseline calculated from \(baselinePoints.count) points: \(Int(baseline)) BPM")
        } else {
            heartRateBaseline = 60.0  // Always default to 60 BPM
            print("� No baseline data, using default: 60 BPM")
        }
        
        // Calculate deviation using most recent heart rate from display data
        if let mostRecentHR = displayDataPoints.last?.heartRate, let baseline = heartRateBaseline {
            currentDeviation = mostRecentHR - baseline
            print("📊 Deviation: \(Int(mostRecentHR)) - \(Int(baseline)) = \(Int(currentDeviation!)) BPM")
        } else {
            currentDeviation = nil
            print("📊 No recent heart rate available for deviation")
        }
        
        print("🔍 FINAL DEBUG: Baseline = \(heartRateBaseline?.description ?? "nil"), Deviation = \(currentDeviation?.description ?? "nil")")
    }
}

// MARK: - Pre-Bedtime Heart Rate Card
struct PreBedtimeHeartRateCard: View {
    let heartRateData: [HeartRateDataPoint]
    let baseline: Double?
    let deviation: Double?
    let isLoading: Bool
    let bedtime: Double
    let date: Date
    let startTime: Date?
    let endTime: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                    .frame(width: 30, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wind down Heart Rate")
                        .font(.headline)
                }
                
                Spacer()
                
                // Current heart rate in top right corner (most recent from display window)
                if let lastHeartRate = heartRateData.last?.heartRate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(lastHeartRate)) BPM")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // Show deviation from baseline if both are available
                        if let deviation = deviation, let baseline = baseline {
                            Text("\(deviation > 0 ? "+" : "")\(Int(deviation)) baseline")
                                .font(.caption2)
                                .foregroundColor(deviation < 0 ? .green : (deviation > 5 ? .orange : .secondary))
                            
                            // DEBUG: Print deviation info
                            .onAppear {
                                print("🔍 DEVIATION DEBUG: Showing deviation \(Int(deviation)) from baseline \(Int(baseline))")
                            }
                        } else if baseline == nil && !heartRateData.isEmpty {
                            Text("establishing baseline")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            // DEBUG: Print baseline establishment info
                            .onAppear {
                                print("🔍 BASELINE DEBUG: No baseline established, data count: \(heartRateData.count)")
                            }
                        } else if let baseline = baseline, deviation == nil {
                            Text("no recent data")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            // DEBUG: Print no deviation info
                            .onAppear {
                                print("🔍 DEVIATION DEBUG: Have baseline \(Int(baseline)) but no deviation calculated")
                            }
                        }
                    }
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if heartRateData.isEmpty {
                Text("No heart rate data available for this time period")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Chart
                HeartRateChart(data: heartRateData, bedtime: bedtime, baseline: baseline, date: date, startTime: startTime, endTime: endTime)
                    .frame(height: 120)
                
                // Only show baseline establishing message if needed
                if baseline == nil && !heartRateData.isEmpty {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Establishing baseline from first 20 minutes...")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Simple Heart Rate Chart
struct HeartRateChart: View {
    let data: [HeartRateDataPoint]
    let bedtime: Double
    let baseline: Double?
    let date: Date
    let startTime: Date?
    let endTime: Date?
    
    // Fixed Y-axis range
    private let minHR: Double = 40
    private let maxHR: Double = 100  // Changed from 120 to 100 as requested
    private var hrRange: Double { maxHR - minHR }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 30 // Leave space for Y-axis labels
            let height = geometry.size.height - 20 // Leave space for X-axis labels
            let chartOriginX: CGFloat = 25
            let chartOriginY: CGFloat = 5
            
            // Calculate time range - use passed times if available, otherwise fall back to bedtime calculation
            let actualStartTime = startTime ?? {
                let calendar = Calendar.current
                let bedtimeHour = Int(bedtime)
                let bedtimeMinute = Int((bedtime - Double(bedtimeHour)) * 60)
                
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
                let bedtimeOnNextDay = calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: nextDay) ?? nextDay
                return calendar.date(byAdding: .hour, value: -1, to: bedtimeOnNextDay) ?? nextDay
            }()
            
            let actualEndTime = endTime ?? {
                let calendar = Calendar.current
                let bedtimeHour = Int(bedtime)
                let bedtimeMinute = Int((bedtime - Double(bedtimeHour)) * 60)
                
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
                return calendar.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: nextDay) ?? nextDay
            }()
            
            let timeRange = actualEndTime.timeIntervalSince(actualStartTime) // Should be 3600 seconds (1 hour)
            
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(.systemBackground))
                    .cornerRadius(8)
                
                // Chart area
                Rectangle()
                    .stroke(Color(.systemGray4), lineWidth: 1)
                    .frame(width: width, height: height)
                    .position(x: chartOriginX + width/2, y: chartOriginY + height/2)
                
                // Horizontal grid lines and Y-axis labels
                ForEach(0..<5) { i in
                    let y = chartOriginY + height * CGFloat(i) / 4
                    let heartRateValue = Int(maxHR - (Double(i) / 4.0) * hrRange)
                    
                    // Grid line
                    Path { path in
                        path.move(to: CGPoint(x: chartOriginX, y: y))
                        path.addLine(to: CGPoint(x: chartOriginX + width, y: y))
                    }
                    .stroke(Color(.systemGray6), lineWidth: 0.5)
                    
                    // Y-axis label
                    Text("\(heartRateValue)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: 12, y: y)
                }
                
                // Vertical grid lines
                ForEach(0..<7) { i in
                    let x = chartOriginX + width * CGFloat(i) / 6
                    
                    Path { path in
                        path.move(to: CGPoint(x: x, y: chartOriginY))
                        path.addLine(to: CGPoint(x: x, y: chartOriginY + height))
                    }
                    .stroke(Color(.systemGray6), lineWidth: 0.5)
                }
                
                // Heart rate line
                if !data.isEmpty {
                    Path { path in
                        for (index, point) in data.enumerated() {
                            let timeProgress = point.date.timeIntervalSince(actualStartTime) / timeRange
                            let x = chartOriginX + width * CGFloat(timeProgress)
                            
                            // Clamp heart rate to our fixed range
                            let clampedHR = max(minHR, min(maxHR, point.heartRate))
                            let hrProgress = (clampedHR - minHR) / hrRange
                            let y = chartOriginY + height * (1 - CGFloat(hrProgress))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.red, lineWidth: 2)
                    
                    // Data points
                    ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                        let timeProgress = point.date.timeIntervalSince(actualStartTime) / timeRange
                        let x = chartOriginX + width * CGFloat(timeProgress)
                        
                        let clampedHR = max(minHR, min(maxHR, point.heartRate))
                        let hrProgress = (clampedHR - minHR) / hrRange
                        let y = chartOriginY + height * (1 - CGFloat(hrProgress))
                        
                        Circle()
                            .fill(Color.red)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }
                }
                
                // Baseline line (if available)
                if let baseline = baseline, baseline >= minHR && baseline <= maxHR {
                    let baselineProgress = (baseline - minHR) / hrRange
                    let baselineY = chartOriginY + height * (1 - CGFloat(baselineProgress))
                    
                    // Baseline line
                    Path { path in
                        path.move(to: CGPoint(x: chartOriginX, y: baselineY))
                        path.addLine(to: CGPoint(x: chartOriginX + width, y: baselineY))
                    }
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    
                    // Baseline label
                    Text("Baseline")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .background(Color(.systemBackground))
                        .position(x: chartOriginX + width - 35, y: baselineY - 10)
                }
                
                // X-axis time labels
                HStack {
                    Text(formatTime(actualStartTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(actualEndTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: width)
                .position(x: chartOriginX + width/2, y: geometry.size.height - 8)
                
                // "No data" message if empty
                if data.isEmpty {
                    Text("No heart rate data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .position(x: geometry.size.width/2, y: geometry.size.height/2)
                }
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// HealthKit Display Card (Activity Summary)
struct HealthKitDisplayCard: View {
    let item: HealthKitDisplayItem

    var body: some View {
        HStack {
            // Display icon with color
            iconView()
                .font(.title2)
                .foregroundColor(iconColor())
                .frame(width: 30, alignment: .center)

            Text(item.name)
            Spacer()
            
            Text(item.displayValue)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func iconView() -> some View {
        if item.icon.count == 1 && item.icon.unicodeScalars.first?.properties.isEmojiPresentation == true {
            Text(item.icon)
        } else {
            Image(systemName: item.icon)
        }
    }

    private func iconColor() -> Color {
        switch item.name {
        case "Steps":
            return .orange
        case "Exercise Time":
            return .red
        case "Time in Daylight":
            return .yellow
        default:
            return .primary
        }
    }
}

// Manual Habit Display Card (User Habits)
struct ManualHabitDisplayCard: View {
    let item: ManualHabitDisplayItem

    var body: some View {
        HStack {
            // Display icon with color
            iconView()
                .font(.title2)
                .foregroundColor(iconColor())
                .frame(width: 30, alignment: .center)

            Text(item.name)
            Spacer()
            
            // Always show checkmark for manual habits
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func iconView() -> some View {
        if item.icon.count == 1 && item.icon.unicodeScalars.first?.properties.isEmojiPresentation == true {
            Text(item.icon)
        } else {
            Image(systemName: item.icon)
        }
    }

    private func iconColor() -> Color {
        switch item.name {
        case "Hot Shower":
            return .blue
        case "Eyemask":
            return .purple
        case "Read Book":
            return .brown
        case "Meditation":
            return .green
        default:
            return .primary
        }
    }
}

// Workout Display Card
struct WorkoutDisplayCard: View {
    let workout: WorkoutDisplayItem

    var body: some View {
        HStack {
            // Workout icon based on type
            workoutIcon()
                .font(.title2)
                .foregroundColor(workoutIconColor())
                .frame(width: 30, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(workout.workoutType)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(workout.timeOfDay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                
                Text(workout.duration)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                // Additional metrics if available
                HStack {
                    if let calories = workout.calories {
                        Text(calories)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let distance = workout.distance {
                        Text(distance)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let heartRate = workout.heartRate {
                        Text(heartRate)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func workoutIcon() -> some View {
        let iconName = workoutTypeIcon(workout.workoutType)
        Image(systemName: iconName)
    }

    private func workoutTypeIcon(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("running") || t.contains("run"):
            return "figure.run"
        case let t where t.contains("cycling") || t.contains("bike"):
            return "figure.outdoor.cycle"
        case let t where t.contains("swimming") || t.contains("swim"):
            return "figure.pool.swim"
        case let t where t.contains("walking") || t.contains("walk"):
            return "figure.walk"
        case let t where t.contains("strength") || t.contains("weight"):
            return "dumbbell"
        case let t where t.contains("yoga"):
            return "figure.yoga"
        case let t where t.contains("hiit") || t.contains("interval"):
            return "bolt"
        default:
            return "figure.mixed.cardio"
        }
    }

    private func workoutIconColor() -> Color {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("running"):
            return .orange
        case let t where t.contains("cycling"):
            return .blue
        case let t where t.contains("swimming"):
            return .cyan
        case let t where t.contains("strength"):
            return .red
        case let t where t.contains("yoga"):
            return .purple
        default:
            return .green
        }
    }
}

// Update Preview Provider
struct DailyHabitsView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let hkManager = HealthKitManager.shared
        let nightlyVM = NightlySleepViewModel(context: context, healthKitManager: hkManager)
        let sampleDate = Date()

        return NavigationView {
             DailyHabitsView(date: sampleDate, context: context, nightlySleepViewModel: nightlyVM, reloadTrigger: UUID())
                .environment(\.managedObjectContext, context)
        }
    }
}