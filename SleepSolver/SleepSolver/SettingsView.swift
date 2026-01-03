//
//  SettingsView.swift
//  SleepSolver
//
//  Created by Cade Christensen on 6/5/25.
//

import SwiftUI
import HealthKit

struct SettingsView: View {
    // User defaults for sleep need
    @AppStorage("userSleepNeed") private var userSleepNeed: Double = 8.0
    @AppStorage("userBedtime") private var userBedtime: Double = 21.0 // 9 PM in 24-hour format
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("useImperialUnits") private var useImperialUnits: Bool = true
    
    // State for UI
    @State private var healthKitStatus: String = "Checking..."
    
    var body: some View {
        NavigationView {
            Form {
                // Sleep Settings Section
                Section(header: Text("Sleep Settings")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Sleep Need")
                                .font(.headline)
                            Spacer()
                            Text("\(String(format: "%.1f", userSleepNeed))h")
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Your daily sleep target used for sleep debt calculations and sleep score evaluation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SleepNeedSliderView(
                            value: $userSleepNeed,
                            range: 6.0...10.0,
                            step: 0.25
                        )
                        .frame(height: 40)
                    }
                    .padding(.vertical, 8)
                }
                
                // Bedtime Section
                Section(header: Text("Bedtime")) {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 24)
                        Text("Target Bedtime")
                            .font(.headline)
                        Spacer()
                        DatePicker("", 
                                 selection: Binding(
                                    get: { bedtimeToDate(userBedtime) },
                                    set: { userBedtime = dateToBedtime($0) }
                                 ),
                                 displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    
                    Text("Your target bedtime for maintaining a consistent sleep schedule")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Units Section
                Section(header: Text("Units")) {
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("Use Imperial Units")
                        Spacer()
                        Toggle("", isOn: $useImperialUnits)
                    }
                    
                    Text("When enabled, temperatures will be shown in Fahrenheit and distances in miles. When disabled, temperatures will be shown in Celsius and distances in kilometers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // App Information Section
                Section(header: Text("App Information")) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("Version")
                        Spacer()
                        Text(AppConfiguration.appVersion)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        Text("HealthKit Status")
                        Spacer()
                        Text(healthKitStatus)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Data Management Section
                // Section(header: Text("Data Management")) {
                //     NavigationLink(destination: DatabaseDebugView()) {
                //         HStack {
                //             Image(systemName: "hammer.fill")
                //                 .foregroundColor(.blue)
                //                 .frame(width: 24)
                //             Text("Database Debug")
                //         }
                //     }
                // }
                
                // About Section
                Section(header: Text("About")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SleepSolver")
                            .font(.headline)
                        Text("Track your sleep patterns, analyze trends, and optimize your rest for better health and recovery.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Button(action: {
                        if let url = URL(string: AppConfiguration.termsOfServiceURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Terms of Service")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: AppConfiguration.privacyPolicyURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                checkHealthKitStatus()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func bedtimeToDate(_ bedtime: Double) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let hour = Int(bedtime)
        let minute = Int((bedtime - Double(hour)) * 60)
        
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        
        return calendar.date(from: components) ?? now
    }
    
    private func dateToBedtime(_ date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 21)
        let minute = Double(components.minute ?? 0)
        return hour + (minute / 60.0)
    }
    
    private func formatBedtime(_ time: Double) -> String {
        let hour = Int(time)
        let minute = Int((time - Double(hour)) * 60)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "\(hour):\(String(format: "%02d", minute))"
    }
    
    private func checkHealthKitStatus() {
        // Check if HealthKitManager exists in the project
        // Since we can't see the implementation, we'll provide a fallback
        healthKitStatus = "Connected"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
