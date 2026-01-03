//
//  SleepScoreDetailView.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 5/24/25.
//

import SwiftUI

struct SleepScoreDetailView: View {
    let sessionV2: SleepSessionV2?
    @Environment(\.presentationMode) var presentationMode
    
    init(sessionV2: SleepSessionV2) {
        self.sessionV2 = sessionV2
    }
    
    // ADDED: Initializer for when no session data is available
    init() {
        self.sessionV2 = nil
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Overall Sleep Score
                    VStack {
                        if isSleepScoreValid {
                            Text("\(sleepScore)")
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .foregroundColor(sleepScoreColor)
                        } else {
                            Text("--")
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    
                    // Show explanation for invalid sleep scores
                    if !isSleepScoreValid {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Insufficient Data")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("Sleep score requires basic sleep data from your watch or device.")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Text("Continue wearing your watch nightly to track your sleep patterns.")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.bottom, 10)
                    }
                    
                    // Sleep Metrics Breakdown - only show if sleep score is valid
                    if isSleepScoreValid {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Sleep Metrics")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            SleepMetricCard(
                                title: "Sleep Duration",
                                score: durationScore,
                                maxScore: 60.0,
                                weightedScore: durationScore,
                                weightedMaxScore: 60.0,
                                value: formatDuration(totalSleepTime),
                                iconName: "bed.double.fill",
                                interpretation: getDurationInterpretation()
                            )
                            
                            SleepMetricCard(
                                title: "Deep Sleep",
                                score: deepScore,
                                maxScore: 15.0,
                                weightedScore: deepScore,
                                weightedMaxScore: 15.0,
                                value: formatDuration(deepDuration),
                                iconName: "moon.zzz.fill",
                                interpretation: getDeepSleepInterpretation()
                            )
                            
                            SleepMetricCard(
                                title: "REM Sleep",
                                score: remScore,
                                maxScore: 15.0,
                                weightedScore: remScore,
                                weightedMaxScore: 15.0,
                                value: formatDuration(remDuration),
                                iconName: "eye.fill",
                                interpretation: getREMInterpretation()
                            )
                            
                            SleepMetricCard(
                                title: "Disturbances",
                                score: awakeScore,
                                maxScore: 10.0,
                                weightedScore: awakeScore,
                                weightedMaxScore: 10.0,
                                value: "\(wakeUps)",
                                iconName: "sleep",
                                interpretation: getWakeUpsInterpretation()
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Sleep Score")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    // MARK: - Computed Properties for Session Data
    private var isSleepScoreValid: Bool {
        if let sessionV2 = sessionV2 {
            return sessionV2.sleepScore > 0
        }
        return false
    }
    
    private var sleepScore: Int {
        if let sessionV2 = sessionV2 {
            return Int(sessionV2.sleepScore)
        }
        return 0
    }
    
    private var totalSleepTime: Double {
        sessionV2?.totalSleepTime ?? 0
    }
    
    private var deepDuration: Double {
        sessionV2?.deepDuration ?? 0
    }
    
    private var remDuration: Double {
        sessionV2?.remDuration ?? 0
    }
    
    private var wakeUps: Int {
        sessionV2?.countAwakePeriods() ?? 0
    }
    
    // MARK: - Component Scores (mirroring SleepSessionV2 logic)
    private var durationScore: Double {
        sessionV2?.calculateDurationScore() ?? 0
    }
    
    private var deepScore: Double {
        sessionV2?.calculateDeepScore() ?? 0
    }
    
    private var remScore: Double {
        sessionV2?.calculateREMScore() ?? 0
    }
    
    private var awakeScore: Double {
        sessionV2?.calculateAwakeScore() ?? 0
    }
    
    private var sleepScoreColor: Color {
        switch sleepScore {
        case 80...100: return .green
        case 60..<80: return .yellow
        default: return .red
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        guard duration > 0 else { return "--" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Interpretations
    private func getDurationInterpretation() -> String {
        let userSleepNeed = UserDefaults.standard.double(forKey: "userSleepNeed")
        let sleepHours = totalSleepTime / 3600.0
        let percentage = userSleepNeed > 0 ? (sleepHours / userSleepNeed) * 100 : 0
        
        switch percentage {
        case 90...110: return "Perfect duration"
        case 80..<90: return "Slightly short"
        case 110..<120: return "Slightly long"
        default: return percentage < 80 ? "Too short" : "Too long"
        }
    }
    
    private func getDeepSleepInterpretation() -> String {
        switch deepScore {
        case 12.0...15.0: return "Optimal deep sleep"
        case 9.0..<12.0: return "Good deep sleep"
        case 6.0..<9.0: return "Fair deep sleep"
        case 3.0..<6.0: return "Low deep sleep"
        default: return "Very low deep sleep"
        }
    }
    
    private func getREMInterpretation() -> String {
        switch remScore {
        case 12.0...15.0: return "Optimal REM sleep"
        case 9.0..<12.0: return "Good REM sleep"
        case 6.0..<9.0: return "Fair REM sleep"
        case 3.0..<6.0: return "Low REM sleep"
        default: return "Very low REM sleep"
        }
    }
    
    private func getWakeUpsInterpretation() -> String {
        switch wakeUps {
        case 0...2: return "Excellent sleep continuity"
        case 3...5: return "Good sleep continuity"
        case 6...10: return "Frequent disturbances"
        default: return "Very fragmented sleep"
        }
    }
}

struct SleepMetricCard: View {
    let title: String
    let score: Double
    let maxScore: Double
    let weightedScore: Double
    let weightedMaxScore: Double
    let value: String
    let iconName: String
    let interpretation: String
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text(interpretation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(String(format: "%.1f/%.0f points", weightedScore, weightedMaxScore))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress bar based on raw score
            ProgressView(value: score, total: maxScore)
                .progressViewStyle(LinearProgressViewStyle(tint: componentScoreColor))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var componentScoreColor: Color {
        let percentage = (score / maxScore) * 100
        switch percentage {
        case 80...100: return .green
        case 60..<80: return .yellow
        default: return .red
        }
    }
}

struct SleepScoreDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let sessionV2 = SleepSessionV2(context: context)
        sessionV2.sleepScore = 85
        sessionV2.totalSleepTime = 28800 // 8 hours
        sessionV2.totalTimeInBed = 32400 // 9 hours
        sessionV2.deepDuration = 7200 // 2 hours
        sessionV2.remDuration = 5760 // 1.6 hours
        // Optionally, mock awake periods if needed for countAwakePeriods()
        return SleepScoreDetailView(sessionV2: sessionV2)
    }
}
