//
//  DatabaseDebugView.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 6/20/25.
//

import SwiftUI
import CoreData
import HealthKit

struct DatabaseDebugView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SleepPeriod.startDateUTC, ascending: false)],
        animation: .default)
    private var sleepPeriods: FetchedResults<SleepPeriod>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SleepSample.startDateUTC, ascending: false)],
        animation: .default)
    private var sleepSamples: FetchedResults<SleepSample>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SleepSessionV2.ownershipDay, ascending: false)],
        animation: .default)
    private var sleepSessions: FetchedResults<SleepSessionV2>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WristTemperature.date, ascending: false)],
        animation: .default)
    private var wristTemperatures: FetchedResults<WristTemperature>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DailyHabitMetrics.date, ascending: false)],
        animation: .default)
    private var habitMetrics: FetchedResults<DailyHabitMetrics>
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Database View", selection: $selectedTab) {
                    Text("Sessions").tag(0)
                    Text("Periods").tag(1)
                    Text("Samples").tag(2)
                    Text("Temps").tag(3)
                    Text("Habits").tag(4)
                    Text("Statistics").tag(5)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                TabView(selection: $selectedTab) {
                    // Sessions Tab
                    sleepSessionsView
                        .tag(0)
                    
                    // Periods Tab
                    sleepPeriodsView
                        .tag(1)
                    
                    // Samples Tab  
                    sleepSamplesView
                        .tag(2)
                    
                    // Temperatures Tab
                    wristTemperaturesView
                        .tag(3)
                    
                    // Habit Metrics Tab
                    habitMetricsView
                        .tag(4)
                    
                    // Statistics Tab
                    statisticsView
                        .tag(5)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Database Debug")
        }
    }
    
    // MARK: - Sleep Periods View
    private var sleepPeriodsView: some View {
        List {
            Section(header: Text("Sleep Periods (\(sleepPeriods.count))")) {
                if sleepPeriods.isEmpty {
                    Text("No sleep periods found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(sleepPeriods, id: \.id) { period in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("ID: \(period.id)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(period.isMajorSleep ? "Major" : "Minor")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(period.isMajorSleep ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            
                            Text("Start: \(period.startDateUTC, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text("End: \(period.endDateUTC, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text("Duration: \(formatDuration(period.duration))")
                                .font(.caption)
                            Text("Timezone: \(period.originalTimeZone)")
                                .font(.caption)
                            Text("Source: \(period.sourceIdentifier)")
                                .font(.caption)
                            Text("Ownership Day: \(period.calculateOwnershipDay(), formatter: dateOnlyFormatter)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Major Sleep: \(period.isMajorSleep ? "Yes" : "No")")
                                .font(.caption)
                                .foregroundColor(period.isMajorSleep ? .green : .orange)
                            Text("Samples: \(period.samples.count)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Resolved: \(period.isResolved ? "Yes" : "No")")
                                .font(.caption)
                                .foregroundColor(period.isResolved ? .green : .red)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
    
    // MARK: - Sleep Samples View
    private var sleepSamplesView: some View {
        List {
            Section(header: Text("Sleep Samples (\(sleepSamples.count))")) {
                if sleepSamples.isEmpty {
                    Text("No sleep samples found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(sleepSamples, id: \.uuid) { sample in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("UUID: \(sample.uuid.uuidString.prefix(8))...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(stageDisplayName(for: sample.stage))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(stageColor(for: sample.stage))
                                    .cornerRadius(4)
                            }
                            
                            Text("Start: \(sample.startDateUTC, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text("End: \(sample.endDateUTC, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text("Duration: \(formatDuration(sample.endDateUTC.timeIntervalSince(sample.startDateUTC)))")
                                .font(.caption)
                            Text("Bundle ID: \(sample.bundleID ?? "Unknown")")
                                .font(.caption)
                                .foregroundColor(.purple)
                            Text("Product Type: \(sample.productType ?? "Unknown")")
                                .font(.caption)
                                .foregroundColor(.indigo)
                            if let period = sample.sleepPeriod {
                                Text("Period: \(period.id)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }    }
    
    // MARK: - Wrist Temperatures View
    private var wristTemperaturesView: some View {
        List {
            Section(header: Text("Wrist Temperatures (\(wristTemperatures.count))")) {
                if wristTemperatures.isEmpty {
                    Text("No wrist temperature samples found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(wristTemperatures, id: \.uuid) { temp in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date: \(temp.date, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text(String(format: "Value: %.2f°", temp.value))
                                .font(.body)
                                .foregroundColor(temp.value == 0 ? .red : .primary)
                            if temp.session != nil {
                                Text("Linked to Session: Yes")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Linked to Session: No")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Habit Metrics View
    private var habitMetricsView: some View {
        List {
            Section(header: Text("Habit Metrics (\(habitMetrics.count))")) {
                if habitMetrics.isEmpty {
                    Text("No habit metrics found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(habitMetrics, id: \.date) { metrics in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Date: \(metrics.date ?? Date(), formatter: dateOnlyFormatter)")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                                if metrics.sleepSession != nil {
                                    Text("Linked")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(4)
                                } else {
                                    Text("Orphaned")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                            
                            Text("Steps: \(Int(metrics.steps))")
                                .font(.caption)
                                .foregroundColor(metrics.steps > 0 ? .primary : .secondary)
                            Text("Exercise Time: \(Int(metrics.exerciseTime)) minutes")
                                .font(.caption)
                                .foregroundColor(metrics.exerciseTime > 0 ? .primary : .secondary)
                            Text("Daylight Time: \(Int(metrics.timeinDaylight)) minutes")
                                .font(.caption)
                                .foregroundColor(metrics.timeinDaylight > 0 ? .primary : .secondary)
                            
                            if let session = metrics.sleepSession {
                                Text("Linked to Session: \(session.ownershipDay, formatter: dateOnlyFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Not linked to any session")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Sleep Sessions View
    private var sleepSessionsView: some View {
        List {
            Section(header: Text("Sleep Sessions (\(sleepSessions.count))")) {
                if sleepSessions.isEmpty {
                    Text("No sleep sessions found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(sleepSessions, id: \.ownershipDay) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Ownership Day: \(session.ownershipDay, formatter: dateOnlyFormatter)")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("Score: \(session.sleepScore)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            
                            Text("Start: \(session.startDateUTC, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text("End: \(session.endDateUTC, formatter: dateTimeFormatter)")
                                .font(.caption)
                            Text("Time in Bed: \(formatDuration(session.totalTimeInBed))")
                                .font(.caption)
                            Text("Sleep Time: \(formatDuration(session.totalSleepTime))")
                                .font(.caption)
                            
                            // Health Metrics
                            HStack {
                                Text("HRV: \(session.averageHRV, specifier: "%.1f") ms")
                                Text("HR: \(session.averageHeartRate, specifier: "%.1f") bpm")
                            }.font(.caption)
                            
                            HStack {
                                Text("SpO2: \(session.averageSpO2 * 100, specifier: "%.1f")%")
                                Text("Resp: \(session.averageRespiratoryRate, specifier: "%.1f") rpm")
                            }.font(.caption)

                            Text("Wrist Temp: \(session.wristTemperature, specifier: "%.2f")°")
                                .font(.caption)

                            // Durations
                            Text("Deep: \(formatDuration(session.deepDuration)) | REM: \(formatDuration(session.remDuration)) | Awake: \(formatDuration(session.totalAwakeTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("Source Periods: \(session.sourcePeriods?.count ?? 0)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            // Show linked periods if any
                            if let periods = session.sourcePeriods?.allObjects as? [SleepPeriod], !periods.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Linked Periods:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(periods.sorted { $0.startDateUTC < $1.startDateUTC }, id: \.id) { period in
                                        Text("  • \(period.id) (\(period.isMajorSleep ? "Major" : "Nap"))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            // Show linked habit metrics if any
                            if let habitMetrics = session.habitMetrics {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Linked Habit Metrics:")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                    Text("  • Date: \(habitMetrics.date ?? Date(), formatter: dateOnlyFormatter)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("  • Steps: \(Int(habitMetrics.steps))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("  • Exercise Time: \(Int(habitMetrics.exerciseTime)) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("  • Daylight Time: \(Int(habitMetrics.timeinDaylight)) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("No Habit Metrics Linked")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Statistics View
    private var statisticsView: some View {
        List {
            Section(header: Text("Database Statistics")) {
                HStack {
                    Text("Total Sleep Periods")
                    Spacer()
                    Text("\(sleepPeriods.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Total Sleep Samples")
                    Spacer()
                    Text("\(sleepSamples.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Sleep Sessions V2")
                    Spacer()
                    Text("\(sleepSessions.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Major Sleep Periods")
                    Spacer()
                    Text("\(sleepPeriods.filter { $0.isMajorSleep }.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Minor Sleep Periods")
                    Spacer()
                    Text("\(sleepPeriods.filter { !$0.isMajorSleep }.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Periods (All have ownership day)")
                    Spacer()
                    Text("\(sleepPeriods.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Resolved Periods")
                    Spacer()
                    Text("\(sleepPeriods.filter { $0.isResolved }.count)")
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Unresolved Periods")
                    Spacer()
                    Text("\(sleepPeriods.filter { !$0.isResolved }.count)")
                        .foregroundColor(.red)
                }
                
                HStack {
                    Text("Total Habit Metrics")
                    Spacer()
                    Text("\(habitMetrics.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Linked Habit Metrics")
                    Spacer()
                    Text("\(habitMetrics.filter { $0.sleepSession != nil }.count)")
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Orphaned Habit Metrics")
                    Spacer()
                    Text("\(habitMetrics.filter { $0.sleepSession == nil }.count)")
                        .foregroundColor(.red)
                }
            }
            
            Section(header: Text("Sample Stages")) {
                ForEach(stageStats, id: \.stage) { stat in
                    HStack {
                        Text(stat.name)
                        Spacer()
                        Text("\(stat.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
    
    private var dateOnlyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
    
    private var stageStats: [(stage: Int16, name: String, count: Int)] {
        let stages: [(Int16, String)] = [
            (0, "In Bed"),
            (1, "Asleep (Unspecified)"),
            (2, "Awake"),
            (3, "Core Sleep"),
            (4, "Deep Sleep"),
            (5, "REM Sleep")
        ]
        
        return stages.map { stage, name in
            let count = sleepSamples.filter { $0.stage == stage }.count
            return (stage: stage, name: name, count: count)
        }
    }
    
    // MARK: - Helper Functions
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func stageDisplayName(for stage: Int16) -> String {
        switch stage {
        case 0: return "In Bed"
        case 1: return "Asleep"
        case 2: return "Awake"
        case 3: return "Core"
        case 4: return "Deep"
        case 5: return "REM"
        default: return "Unknown"
        }
    }
    
    private func stageColor(for stage: Int16) -> Color {
        switch stage {
        case 0: return Color.gray.opacity(0.2)
        case 1: return Color.green.opacity(0.2)
        case 2: return Color.orange.opacity(0.2)
        case 3: return Color.blue.opacity(0.2)
        case 4: return Color.purple.opacity(0.2)
        case 5: return Color.cyan.opacity(0.2)
        default: return Color.gray.opacity(0.2)
        }
    }
}

struct DatabaseDebugView_Previews: PreviewProvider {
    static var previews: some View {
        DatabaseDebugView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
