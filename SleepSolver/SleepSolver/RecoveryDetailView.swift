//
//  RecoveryDetailView.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import SwiftUI
import CoreData

struct RecoveryDetailView: View {
    let sessionV2: SleepSessionV2?
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("useImperialUnits") private var useImperialUnits: Bool = true
    @State private var availableSessionsCount: Int = 0

    init(sessionV2: SleepSessionV2?) {
        self.sessionV2 = sessionV2
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session = sessionV2 {
                        Text("Recovery Status")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom, 10)
                        
                        // Show baseline progress if baselines haven't been calculated yet
                        if let session = sessionV2, session.hrvBaseline == -100.0 {
                            BaselineProgressView(availableCount: availableSessionsCount, requiredCount: 7)
                                .padding(.bottom, 10)
                        }

                        RecoveryStatusRow(
                            metricName: "HRV", 
                            zScore: session.hrvStatus, 
                            currentValue: session.averageHRV, 
                            baseline: session.hrvBaseline != -100.0 ? session.hrvBaseline : nil,
                            unit: "ms", 
                            isHigherBetter: true, 
                            iconName: "waveform.path.ecg.rectangle.fill"
                        )
                        RecoveryStatusRow(
                            metricName: "RHR", 
                            zScore: session.rhrStatus, 
                            currentValue: session.averageHeartRate, 
                            baseline: session.rhrBaseline != -100.0 ? session.rhrBaseline : nil,
                            unit: "bpm", 
                            isHigherBetter: false, 
                            iconName: "heart.fill"
                        )
                        RecoveryStatusRow(
                            metricName: "SpO2", 
                            zScore: session.spo2Status, 
                            currentValue: session.averageSpO2, 
                            baseline: session.spo2Baseline != -100.0 ? session.spo2Baseline : nil,
                            unit: "%", 
                            isHigherBetter: true, 
                            iconName: "lungs.fill"
                        )
                        RecoveryStatusRow(
                            metricName: "Respiratory Rate", 
                            zScore: session.respStatus, 
                            currentValue: session.averageRespiratoryRate, 
                            baseline: session.respBaseline != -100.0 ? session.respBaseline : nil,
                            unit: "rpm", 
                            isHigherBetter: false, 
                            iconName: "wind"
                        )
                        RecoveryStatusRow(
                            metricName: "Temperature", 
                            zScore: session.temperatureStatus, 
                            currentValue: useImperialUnits ? celsiusToFahrenheit(session.wristTemperature) : session.wristTemperature, 
                            baseline: session.temperatureBaseline != -100.0 ? (useImperialUnits ? celsiusToFahrenheit(session.temperatureBaseline) : session.temperatureBaseline) : nil,
                            unit: useImperialUnits ? "°F" : "°C", 
                            isHigherBetter: false, 
                            iconName: "thermometer",
                            showOnlyDeviation: true
                        )

                    } else {
                        Text("No recovery data available for this session.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Recovery Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                if let session = sessionV2 {
                    let calculator = RecoveryScoreCalculator(context: viewContext)
                    availableSessionsCount = calculator.getAvailableSessionsCount(for: session.ownershipDay)
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Convert Celsius to Fahrenheit
    private func celsiusToFahrenheit(_ celsius: Double) -> Double {
        return (celsius * 9.0 / 5.0) + 32.0
    }
}

// MARK: - Baseline Progress View

struct BaselineProgressView: View {
    let availableCount: Int
    let requiredCount: Int
    
    var progressPercentage: Double {
        return min(Double(availableCount) / Double(requiredCount), 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Building Your Baseline")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(availableCount)/\(requiredCount) sleep sessions with health data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Progress percentage
                Text("\(Int(progressPercentage * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * CGFloat(progressPercentage), height: 8)
                }
            }
            .frame(height: 8)
            
            if availableCount < requiredCount {
                Text("Recovery analysis will be available after \(requiredCount - availableCount) more sleep sessions with health data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Baseline established! Recovery analysis is available for all sessions.")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemOrange).opacity(0.1))
        .cornerRadius(12)
    }
}

struct RecoveryStatusRow: View {
    let metricName: String
    let zScore: Double
    let currentValue: Double
    let baseline: Double?
    let unit: String
    let isHigherBetter: Bool?
    let penalizeDirection: RecoveryPenalizeDirection?
    let iconName: String
    let showOnlyDeviation: Bool
    
    // Convenience initializers
    init(metricName: String, zScore: Double, currentValue: Double, baseline: Double? = nil, unit: String, isHigherBetter: Bool, iconName: String, showOnlyDeviation: Bool = false) {
        self.metricName = metricName
        self.zScore = zScore
        self.currentValue = currentValue
        self.baseline = baseline
        self.unit = unit
        self.isHigherBetter = isHigherBetter
        self.penalizeDirection = nil
        self.iconName = iconName
        self.showOnlyDeviation = showOnlyDeviation
    }
    
    init(metricName: String, zScore: Double, currentValue: Double, baseline: Double? = nil, unit: String, penalizeDirection: RecoveryPenalizeDirection, iconName: String, showOnlyDeviation: Bool = false) {
        self.metricName = metricName
        self.zScore = zScore
        self.currentValue = currentValue
        self.baseline = baseline
        self.unit = unit
        self.isHigherBetter = nil
        self.penalizeDirection = penalizeDirection
        self.iconName = iconName
        self.showOnlyDeviation = showOnlyDeviation
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with icon, metric name, and current value
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(hasInvalidData ? .secondary : statusColor)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(metricName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !hasInvalidData {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrentValue())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let deviationText = formatDeviation() {
                        Text(deviationText)
                            .font(.caption)
                            .foregroundColor(deviationColor)
                            .fontWeight(.medium)
                    }
                }
            }
            
            // Z-Score visualization bar - only show if we have valid data
            if !hasInvalidData {
                ZScoreBarView(zScore: zScore, color: statusColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    /// Determines if the current data is invalid (no data available)
    private var hasInvalidData: Bool {
        // Check if z-score is the sentinel value (-100) indicating no baseline calculated
        if zScore == -100.0 {
            return true
        }
        
        // General case: current value is 0
        if currentValue == 0 {
            return true
        }
        
        // Special case for temperature in Fahrenheit: 32°F indicates 0°C (no data)
        if unit.lowercased().contains("°f") && abs(currentValue - 32.0) < 0.01 {
            return true
        }
        
        return false
    }
    
    private func formatCurrentValue() -> String {
        // Check for invalid data - this must happen before any unit conversions
        if hasInvalidData {
            return "--"
        }
        
        // For temperature, show only deviation from baseline
        if showOnlyDeviation, let baseline = baseline, baseline != -100.0 {
            let deviation = currentValue - baseline
            let sign = deviation >= 0 ? "+" : ""
            switch unit.lowercased() {
            case "°f":
                return String(format: "%@%.2f°F", sign, deviation)
            case "°c":
                return String(format: "%@%.2f°C", sign, deviation)
            default:
                return String(format: "%@%.1f \(unit)", sign, deviation)
            }
        }
        
        // Format current value only
        switch unit.lowercased() {
        case "bpm":
            return "\(Int(currentValue)) bpm"
        case "ms":
            // HRV uses 1 decimal
            return String(format: "%.1f ms", currentValue)
        case "%":
            return String(format: "%.1f%%", currentValue * 100)
        case "rpm":
            // Respiratory rate uses 1 decimal
            return String(format: "%.1f rpm", currentValue)
        case "°f":
            // Temperature uses 2 decimals
            return String(format: "%.2f°F", currentValue)
        case "°c":
            // Temperature uses 2 decimals
            return String(format: "%.2f°C", currentValue)
        default:
            return String(format: "%.1f \(unit)", currentValue)
        }
    }
    
    private func formatDeviation() -> String? {
        // Don't show deviation for temperature when showing only deviation, or when no baseline, or when data is invalid
        if showOnlyDeviation || baseline == nil || baseline == -100.0 || hasInvalidData {
            return nil
        }
        
        guard let baseline = baseline else { return nil }
        
        let deviation = currentValue - baseline
        if abs(deviation) < 0.01 { // Very small deviations aren't meaningful
            return nil
        }
        
        let sign = deviation >= 0 ? "+" : ""
        
        switch unit.lowercased() {
        case "bpm":
            return String(format: "%@%.0f bpm", sign, deviation)
        case "ms":
            return String(format: "%@%.1f ms", sign, deviation)
        case "%":
            return String(format: "%@%.1f%%", sign, deviation * 100)
        case "rpm":
            return String(format: "%@%.1f rpm", sign, deviation)
        case "°f":
            return String(format: "%@%.2f°F", sign, deviation)
        case "°c":
            return String(format: "%@%.2f°C", sign, deviation)
        default:
            return String(format: "%@%.1f \(unit)", sign, deviation)
        }
    }
    
    private var deviationColor: Color {
        guard let baseline = baseline, baseline != -100.0, !hasInvalidData else {
            return .secondary
        }
        
        let deviation = currentValue - baseline
        if abs(deviation) < 0.01 {
            return .secondary // Neutral for values very close to baseline
        } else if deviation > 0 {
            return .green
        } else {
            return .red
        }
    }

    private func formatValue() -> String {
        // This method is kept for backward compatibility but not used in the new layout
        return formatCurrentValue()
    }
    
    private func formatZScore() -> String {
        // This method is kept for backward compatibility but not used in the new layout
        if zScore == -100.0 {
            return "N/A"
        }
        
        let sign = zScore >= 0 ? "+" : ""
        return String(format: "%@%.2f", sign, zScore)
    }
    
    private var zScoreColor: Color {
        // This method is kept for backward compatibility but not used in the new layout
        if zScore == -100.0 {
            return .secondary
        }
        
        if abs(zScore) < 0.1 {
            return .secondary // Neutral for values very close to 0
        } else if zScore > 0 {
            return .green
        } else {
            return .red
        }
    }

    private var statusText: String {
        // Check for sentinel value first
        if zScore == -100.0 {
            return "Building baseline"
        }
        
        if let isHigherBetter = isHigherBetter {
            return zScore.recoveryStatusString(isHigherBetter: isHigherBetter).capitalized
        } else if let penalizeDirection = penalizeDirection {
            return zScore.flexibleRecoveryStatusString(penalizeDirection: penalizeDirection).capitalized
        } else {
            return "Not available"
        }
    }

    private var statusColor: Color {
        // Check for sentinel value first
        if zScore == -100.0 {
            return .orange
        }
        
        if let isHigherBetter = isHigherBetter {
            return zScore.recoveryColor(isHigherBetter: isHigherBetter)
        } else if let penalizeDirection = penalizeDirection {
            return zScore.flexibleRecoveryStatus(penalizeDirection: penalizeDirection).color
        } else {
            return .secondary
        }
    }
}

struct ZScoreBarView: View {
    let zScore: Double
    let color: Color
    
    private let barHeight: CGFloat = 8
    private let circleSize: CGFloat = 16
    private let minZScore: Double = -3
    private let maxZScore: Double = 3
    
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                
                ZStack(alignment: .leading) {
                    // Background bar
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color(.systemGray4))
                        .frame(height: barHeight)
                    
                    // Expected range indicators (vertical lines at ±1.5)
                    let negativeThresholdPosition = CGFloat((-1.5 - minZScore) / (maxZScore - minZScore)) * width
                    let positiveThresholdPosition = CGFloat((1.5 - minZScore) / (maxZScore - minZScore)) * width
                    
                    // -1.5 indicator
                    Rectangle()
                        .fill(Color(.systemGray2))
                        .frame(width: 1, height: barHeight + 4)
                        .offset(x: negativeThresholdPosition - 0.5)
                    
                    // +1.5 indicator  
                    Rectangle()
                        .fill(Color(.systemGray2))
                        .frame(width: 1, height: barHeight + 4)
                        .offset(x: positiveThresholdPosition - 0.5)
                    
                    // Center line (0)
                    let centerPosition = CGFloat((0 - minZScore) / (maxZScore - minZScore)) * width
                    Rectangle()
                        .fill(Color(.systemGray))
                        .frame(width: 1, height: barHeight + 2)
                        .offset(x: centerPosition - 0.5)
                    
                    // Z-Score position circle
                    if !zScore.isNaN {
                        let clampedZScore = max(minZScore, min(maxZScore, zScore))
                        let position = CGFloat((clampedZScore - minZScore) / (maxZScore - minZScore)) * width
                        
                        Circle()
                            .fill(color)
                            .frame(width: circleSize, height: circleSize)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .offset(x: position - circleSize / 2)
                    }
                }
            }
            .frame(height: circleSize)
        }
    }
}


struct RecoveryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview with established baseline
            withBaseline
                .previewDisplayName("With Baseline")
            
            // Preview without enough sessions for baseline
            buildingBaseline
                .previewDisplayName("Building Baseline")
        }
    }
    
    static var withBaseline: some View {
        let context = PersistenceController.preview.container.viewContext
        let sessionV2 = SleepSessionV2(context: context)
        sessionV2.ownershipDay = Date()
        sessionV2.hrvStatus = 0.3  // Optimal z-score (within ±0.5 std)
        sessionV2.rhrStatus = -0.7  // Good z-score (within ±1.0 std)
        sessionV2.spo2Status = -0.8  // Good z-score (within ±1.0 std)
        sessionV2.respStatus = 0.4   // Optimal z-score (within ±0.5 std)
        sessionV2.temperatureStatus = 1.2  // Attention z-score (beyond ±1.0 std)
        sessionV2.sleepScore = 92
        
        // Add current metric values for display
        sessionV2.averageHRV = 42.3
        sessionV2.averageHeartRate = 58.0
        sessionV2.averageSpO2 = 0.97
        sessionV2.averageRespiratoryRate = 14.2
        sessionV2.wristTemperature = 96.8
        
        // Add baseline values (not sentinel values)
        sessionV2.hrvBaseline = 38.5
        sessionV2.rhrBaseline = 61.0
        sessionV2.spo2Baseline = 0.975
        sessionV2.respBaseline = 15.0
        sessionV2.temperatureBaseline = 97.2
        
        return RecoveryDetailView(sessionV2: sessionV2)
    }
    
    static var buildingBaseline: some View {
        let context = PersistenceController.preview.container.viewContext
        let sessionNoBaseline = SleepSessionV2(context: context)
        sessionNoBaseline.ownershipDay = Date()
        sessionNoBaseline.hrvStatus = -100.0  // Sentinel value indicating no calculation
        sessionNoBaseline.rhrStatus = -100.0
        sessionNoBaseline.spo2Status = -100.0
        sessionNoBaseline.respStatus = -100.0
        sessionNoBaseline.temperatureStatus = -100.0
        sessionNoBaseline.sleepScore = 0
        
        // Add current metric values for display
        sessionNoBaseline.averageHRV = 42.3
        sessionNoBaseline.averageHeartRate = 58.0
        sessionNoBaseline.averageSpO2 = 0.97
        sessionNoBaseline.averageRespiratoryRate = 14.2
        sessionNoBaseline.wristTemperature = 96.8
        
        // Baseline values are sentinel values (will be default -100.0)
        sessionNoBaseline.hrvBaseline = -100.0
        sessionNoBaseline.rhrBaseline = -100.0
        sessionNoBaseline.spo2Baseline = -100.0
        sessionNoBaseline.respBaseline = -100.0
        sessionNoBaseline.temperatureBaseline = -100.0
        
        return RecoveryDetailView(sessionV2: sessionNoBaseline)
    }
}
