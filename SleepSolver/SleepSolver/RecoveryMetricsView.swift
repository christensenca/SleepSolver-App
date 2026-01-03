import SwiftUI

// MARK: - Data Structures for Mock-up

/// Represents the status of a single recovery metric.
enum RecoveryMetricStatus: Int {
    case attention = 1
    case good = 2
    case optimal = 3
    case unknown = 0

    var color: Color {
        switch self {
        case .optimal: return Color(red: 0.0, green: 0.6, blue: 0.0) // Darker green for optimal
        case .good: return .green // Regular green for good (was blue)
        case .attention: return .red
        case .unknown: return .gray.opacity(0.2) // Very subtle indication for unknown status
        }
    }
    
    /// Creates a RecoveryMetricStatus from a string value.
    /// - Parameter string: The string value representing the status.
    /// - Returns: The corresponding RecoveryMetricStatus, or .unknown if the string does not match any status.
    static func from(string: String?) -> RecoveryMetricStatus {
        switch string?.lowercased() {
        case "optimal":
            return .optimal
        case "good":
            return .good
        case "attention":
            return .attention
        default:
            return .unknown
        }
    }
}

/// A struct to hold the mock data for a single gauge.
struct RecoveryMetricData {
    let icon: String
    let status: RecoveryMetricStatus
}

// MARK: - Main View for the Recovery Metrics Section

struct RecoveryMetricsView: View {
    
    let session: SleepSessionV2?
    
    private var metrics: [RecoveryMetricData] {
        var metricsList: [RecoveryMetricData] = []
        
        // Check if we have valid recovery data:
        // 1. Session must exist
        // 2. Session must be finalized
        let hasValidRecoveryData = session?.isFinalized == true
        
        // HRV (higher is better)
        let hrvStatus: RecoveryMetricStatus = {
            guard hasValidRecoveryData, let session = session else { return .unknown }
            // Check for invalid data: z-score is sentinel value (-100) or current value is 0
            if session.hrvStatus == -100.0 || session.averageHRV == 0 {
                return .unknown
            }
            return session.hrvStatus.recoveryStatus(isHigherBetter: true)
        }()
        metricsList.append(RecoveryMetricData(icon: "waveform.path.ecg.rectangle.fill", status: hrvStatus))
        
        // RHR (lower is better)
        let rhrStatus: RecoveryMetricStatus = {
            guard hasValidRecoveryData, let session = session else { return .unknown }
            // Check for invalid data: z-score is sentinel value (-100) or current value is 0
            if session.rhrStatus == -100.0 || session.averageHeartRate == 0 {
                return .unknown
            }
            return session.rhrStatus.recoveryStatus(isHigherBetter: false)
        }()
        metricsList.append(RecoveryMetricData(icon: "heart.fill", status: rhrStatus))
        
        // Temperature (lower is better)
        let temperatureStatus: RecoveryMetricStatus = {
            guard hasValidRecoveryData, let session = session else { return .unknown }
            // Check for invalid data: z-score is sentinel value (-100) or current value is 0
            if session.temperatureStatus == -100.0 || session.wristTemperature == 0 {
                return .unknown
            }
            return session.temperatureStatus.recoveryStatus(isHigherBetter: false)
        }()
        metricsList.append(RecoveryMetricData(icon: "thermometer", status: temperatureStatus))
        
        // SpO2 (higher is better)
        let spo2Status: RecoveryMetricStatus = {
            guard hasValidRecoveryData, let session = session else { return .unknown }
            // Check for invalid data: z-score is sentinel value (-100) or current value is 0
            if session.spo2Status == -100.0 || session.averageSpO2 == 0 {
                return .unknown
            }
            return session.spo2Status.recoveryStatus(isHigherBetter: true)
        }()
        metricsList.append(RecoveryMetricData(icon: "lungs.fill", status: spo2Status))
        
        // Respiratory Rate (lower is better)
        let respStatus: RecoveryMetricStatus = {
            guard hasValidRecoveryData, let session = session else { return .unknown }
            // Check for invalid data: z-score is sentinel value (-100) or current value is 0
            if session.respStatus == -100.0 || session.averageRespiratoryRate == 0 {
                return .unknown
            }
            return session.respStatus.recoveryStatus(isHigherBetter: false)
        }()
        metricsList.append(RecoveryMetricData(icon: "wind", status: respStatus))
        
        return metricsList
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Recovery Metrics")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 15) {
                ForEach(metrics, id: \.icon) { metric in
                    CircularMetricGaugeView(data: metric)
                }
            }
        }
    }
}

// MARK: - Circular Metric Gauge View

struct CircularMetricGaugeView: View {
    let data: RecoveryMetricData
    private let totalSegments = 3
    private let segmentGap: Angle = .degrees(8)
    private let gaugeSize: CGFloat = 50

    var body: some View {
        ZStack {
            // Central Icon
            Image(systemName: data.icon)
                .font(.system(size: 20))
                .foregroundColor(data.status == .unknown ? .secondary : .primary)

            // Gauge Segments
            ForEach(Array(0..<totalSegments), id: \.self) { i in
                let startAngle = angle(for: i)
                let endAngle = startAngle + segmentAngle()
                
                let segmentColor: Color = {
                    if data.status == .unknown {
                        // For unknown status, show all segments in subtle gray
                        return Color.gray.opacity(0.15)
                    } else {
                        // For known status, fill based on status value
                        let isFilled = i < data.status.rawValue
                        return isFilled ? data.status.color : Color.gray.opacity(0.3)
                    }
                }()

                Path { path in
                    path.addArc(center: CGPoint(x: gaugeSize / 2, y: gaugeSize / 2),
                                radius: gaugeSize / 2 - 2, // a bit of padding
                                startAngle: startAngle,
                                endAngle: endAngle,
                                clockwise: false)
                }
                .stroke(segmentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .frame(width: gaugeSize, height: gaugeSize)
            .rotationEffect(.degrees(-90 - (segmentGap.degrees / 2))) // Start from top
        }
        .frame(width: gaugeSize, height: gaugeSize)
    }

    private func segmentAngle() -> Angle {
        return .degrees((360 - Double(totalSegments) * segmentGap.degrees) / Double(totalSegments))
    }

    private func angle(for index: Int) -> Angle {
        let segmentAndGap = segmentAngle() + segmentGap
        return .degrees(Double(index) * segmentAndGap.degrees)
    }
}


// MARK: - Preview

#Preview {
    // Function to create a mock session for previewing
    func createMockSession() -> SleepSessionV2 {
        let context = PersistenceController.preview.container.viewContext
        let session = SleepSessionV2(context: context)
        session.ownershipDay = Date()
        session.isFinalized = true       // Mark as finalized to show recovery data
        session.hrvStatus = 0.3      // Optimal z-score (within ±0.5 std)
        session.rhrStatus = -0.7     // Good z-score (within ±1.0 std)  
        session.temperatureStatus = 1.2  // Attention z-score (beyond ±1.0 std)
        session.respStatus = 0.4     // Optimal z-score (within ±0.5 std, flexible interpretation)
        session.spo2Status = -0.8    // Good z-score (within ±1.0 std, flexible interpretation)
        return session
    }
    
    // Function to create a mock session without recovery data
    func createEmptyMockSession() -> SleepSessionV2 {
        let context = PersistenceController.preview.container.viewContext
        let session = SleepSessionV2(context: context)
        session.ownershipDay = Date()
        session.isFinalized = false      // Not finalized, so recovery data won't show
        // All recovery metrics will be 0.0 (default values)
        return session
    }
    
    return ScrollView {
        VStack(spacing: 20) {
            VStack {
                Text("With Recovery Data")
                    .font(.title2)
                    .bold()
                RecoveryMetricsView(session: createMockSession())
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            
            VStack {
                Text("Without Recovery Data (Not Finalized)")
                    .font(.title2)
                    .bold()
                RecoveryMetricsView(session: createEmptyMockSession())
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            
            VStack {
                Text("No Sleep Session")
                    .font(.title2)
                    .bold()
                RecoveryMetricsView(session: nil)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
