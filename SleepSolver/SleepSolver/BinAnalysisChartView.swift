import SwiftUI
import Charts

struct BinAnalysisChartView: View {
    let result: BinAnalysisResult
    @State private var selectedBin: HealthMetricBin? = nil
    @State private var showingDetails = false
    @State private var selectedXValue: String? = nil
    
    // Computed property to get relative values (deviation from baseline)
    private var binsWithRelativeValues: [(bin: HealthMetricBin, relativeValue: Double)] {
        result.bins.map { bin in
            (bin: bin, relativeValue: bin.averageSleepMetric - result.baseline)
        }
    }
    
    // Helper function for smart unit scaling and display formatting
    private func formatRangeForDisplay(_ range: String) -> String {
        // Extract the metric type from the health metric name
        let healthMetricName = result.healthMetricName.lowercased()
        
        if healthMetricName.contains("steps") {
            // Convert steps to thousands (e.g., "5000-8000 steps" → "5-8k")
            let components = range.replacingOccurrences(of: " steps", with: "").split(separator: "-")
            if components.count == 2,
               let lower = Double(components[0]),
               let upper = Double(components[1]) {
                let lowerK = Int(lower / 1000)
                let upperK = Int(upper / 1000)
                return "\(lowerK)-\(upperK)k"
            }
        } else if healthMetricName.contains("time") || healthMetricName.contains("exercise") {
            // Convert minutes to hours for longer durations (e.g., "60-90 min" → "1-1.5h")
            let components = range.replacingOccurrences(of: " min", with: "").split(separator: "-")
            if components.count == 2,
               let lower = Double(components[0]),
               let upper = Double(components[1]) {
                if upper >= 60 {
                    let lowerH = lower / 60
                    let upperH = upper / 60
                    if lowerH == floor(lowerH) && upperH == floor(upperH) {
                        return "\(Int(lowerH))-\(Int(upperH))h"
                    } else {
                        return String(format: "%.1f-%.1fh", lowerH, upperH)
                    }
                } else {
                    return "\(Int(lower))-\(Int(upper))m"
                }
            }
        }
        
        // Default: return original range but shortened
        return range.replacingOccurrences(of: " steps", with: "").replacingOccurrences(of: " min", with: "m")
    }
    
    // Helper function to format y-axis labels with appropriate units
    private func formatYAxisLabel(_ value: Double) -> String {
        let sleepMetricName = result.sleepMetricName.lowercased()
        
        // Determine units based on the sleep metric type
        if sleepMetricName.contains("duration") || 
           sleepMetricName.contains("sleep") && sleepMetricName.contains("time") ||
           sleepMetricName.contains("deep sleep") ||
           sleepMetricName.contains("rem sleep") {
            // Sleep Duration, Deep Sleep, REM Sleep - typically in hours
            if abs(value) >= 1.0 {
                return String(format: "%.1fh", value)
            } else {
                return String(format: "%.0fm", value * 60) // Convert to minutes for small values
            }
        } else if sleepMetricName.contains("awake") {
            // Total Awake Time - in hours, but often fractional
            if abs(value) >= 1.0 {
                return String(format: "%.1fh", value)
            } else {
                return String(format: "%.0fm", value * 60) // Convert to minutes for small values
            }
        } else if sleepMetricName.contains("score") {
            // Sleep Score - typically 0-100 scale
            return String(format: "%.0f", value)
        } else if sleepMetricName.contains("hrv") {
            // HRV - typically in milliseconds
            return String(format: "%.0fms", value)
        } else if sleepMetricName.contains("heart") && sleepMetricName.contains("rate") {
            // Heart Rate - beats per minute
            return String(format: "%.0f bpm", value)
        } else {
            // Default formatting for unknown metrics
            if abs(value) >= 10 {
                return String(format: "%.0f", value)
            } else {
                return String(format: "%.1f", value)
            }
        }
    }
    
    // Function to share chart as image
    private func shareChart() {
        // Create a UIActivityViewController to share the chart with forced dark mode
        let darkView = self.environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: darkView)
        renderer.scale = 3.0 // High resolution
        
        if let image = renderer.uiImage {
            let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            
            // Present the share sheet
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                
                // For iPad - set popover presentation
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = rootViewController.view
                    popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                rootViewController.present(activityVC, animated: true)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with health metric info
            HStack {
                Image(systemName: result.healthMetricIcon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.healthMetricName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("vs Avg \(result.sleepMetricName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    shareChart()
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .padding(8)
            }
            
            // Chart or insufficient data message
            if result.isValid && !result.bins.isEmpty {
                Chart(binsWithRelativeValues, id: \.bin.id) { item in
                    BarMark(
                        x: .value("Range", formatRangeForDisplay(item.bin.range)),
                        y: .value("Deviation", item.relativeValue)
                    )
                    .foregroundStyle(item.relativeValue >= 0 ? Color.green.gradient : Color.red.gradient)
                    .opacity(selectedBin?.id == item.bin.id ? 1.0 : 0.7)
                    
                    // Add a reference line at zero
                    RuleMark(y: .value("Baseline", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(.gray)
                        .opacity(0.7)
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatYAxisLabel(doubleValue))
                                    .font(.caption)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(orientation: .vertical) // Rotate labels vertically
                    }
                }
                // Include zero to show the baseline clearly
                .chartYScale(domain: .automatic(includesZero: true))
                .coordinateSpace(name: "chart")
                .chartXSelection(value: $selectedXValue)
                .onChange(of: selectedXValue) { oldValue, newValue in
                    // Use SwiftUI Charts' built-in selection to find the selected bin
                    if let selectedRange = newValue,
                       let selectedBinData = binsWithRelativeValues.first(where: {
                           formatRangeForDisplay($0.bin.range) == selectedRange
                       }) {
                        self.selectedBin = selectedBinData.bin
                        showingDetails = true
                    }
                }
                
            } else {
                // Insufficient data message
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    if case .insufficientData(let current, let required) = result.status {
                        VStack(spacing: 4) {
                            Text("Insufficient Data")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            Text("Need \(required) days, have \(current)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No data available")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showingDetails) {
            if let selectedBin = selectedBin {
                NavigationView {
                    BinDetailView(
                        bin: selectedBin,
                        healthMetricName: result.healthMetricName,
                        sleepMetricName: result.sleepMetricName,
                        baseline: result.baseline
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDetails = false
                            }
                        }
                    }
                }
                .presentationDetents([.fraction(0.5)])
            }
        }
    }
}

// Detail view for showing bin information
struct BinDetailView: View {
    let bin: HealthMetricBin
    let healthMetricName: String
    let sleepMetricName: String
    let baseline: Double
    
    private var relativeValue: Double {
        bin.averageSleepMetric - baseline
    }
    
    private var getUnitFromHealthMetric: String {
        if healthMetricName.lowercased().contains("steps") {
            return "steps"
        } else if healthMetricName.lowercased().contains("time") || healthMetricName.lowercased().contains("exercise") {
            return "min"
        } else {
            return ""
        }
    }
    
    // Helper function to format values with proper units for detail view
    private func formatDetailValue(_ value: Double) -> String {
        let metricName = sleepMetricName.lowercased()
        
        if metricName.contains("duration") || 
           metricName.contains("sleep") && metricName.contains("time") ||
           metricName.contains("deep sleep") ||
           metricName.contains("rem sleep") {
            // Sleep Duration, Deep Sleep, REM Sleep - in hours
            return String(format: "%.1f hours", value)
        } else if metricName.contains("awake") {
            // Total Awake Time - in hours
            return String(format: "%.1f hours", value)
        } else if metricName.contains("score") {
            // Sleep Score - 0-100 scale
            return String(format: "%.0f", value)
        } else if metricName.contains("hrv") {
            // HRV - in milliseconds
            return String(format: "%.1f ms", value)
        } else if metricName.contains("heart") && metricName.contains("rate") {
            // Heart Rate - beats per minute
            return String(format: "%.0f bpm", value)
        } else {
            // Default formatting
            return String(format: "%.1f", value)
        }
    }
    
    // Helper function to format values with sign and proper units
    private func formatDetailValueWithSign(_ value: Double) -> String {
        let metricName = sleepMetricName.lowercased()
        let sign = value >= 0 ? "+" : ""
        
        if metricName.contains("duration") || 
           metricName.contains("sleep") && metricName.contains("time") ||
           metricName.contains("deep sleep") ||
           metricName.contains("rem sleep") {
            // Sleep Duration, Deep Sleep, REM Sleep - in hours
            return String(format: "%@%.1f hours", sign, value)
        } else if metricName.contains("awake") {
            // Total Awake Time - in hours
            return String(format: "%@%.1f hours", sign, value)
        } else if metricName.contains("score") {
            // Sleep Score - 0-100 scale
            return String(format: "%@%.0f", sign, value)
        } else if metricName.contains("hrv") {
            // HRV - in milliseconds
            return String(format: "%@%.1f ms", sign, value)
        } else if metricName.contains("heart") && metricName.contains("rate") {
            // Heart Rate - beats per minute
            return String(format: "%@%.0f bpm", sign, value)
        } else {
            // Default formatting
            return String(format: "%@%.1f", sign, value)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(healthMetricName): \(bin.range)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            // Metrics
            VStack(spacing: 16) {
                // Sample count
                HStack {
                    Image(systemName: "number.circle")
                        .foregroundColor(.blue)
                    Text("Sample Count:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(bin.sampleCount) days")
                        .fontWeight(.semibold)
                }
                
                Divider()
                
                // Absolute sleep metric value
                HStack {
                    Image(systemName: "moon.stars")
                        .foregroundColor(.purple)
                    Text("Average \(sleepMetricName):")
                        .fontWeight(.medium)
                    Spacer()
                    Text(formatDetailValue(bin.averageSleepMetric))
                        .fontWeight(.semibold)
                }
                
                Divider()
                
                // Relative to baseline
                HStack {
                    Image(systemName: relativeValue >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(relativeValue >= 0 ? .green : .red)
                    Text("From Baseline:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(formatDetailValueWithSign(relativeValue))
                        .fontWeight(.semibold)
                        .foregroundColor(relativeValue >= 0 ? .green : .red)
                }
                
                Divider()
                
                // Baseline reference
                HStack {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.gray)
                    Text("Time Period Baseline:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(formatDetailValue(baseline))
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    let sampleBins = [
        HealthMetricBin(range: "0-3000 steps", lowerBound: 0, upperBound: 3000, averageSleepMetric: 82.5, sampleCount: 15),
        HealthMetricBin(range: "3000-6000 steps", lowerBound: 3000, upperBound: 6000, averageSleepMetric: 85.3, sampleCount: 12),
        HealthMetricBin(range: "6000-9000 steps", lowerBound: 6000, upperBound: 9000, averageSleepMetric: 88.1, sampleCount: 8)
    ]
    
    let sampleResult = BinAnalysisResult(
        healthMetricName: "Steps",
        healthMetricIcon: "figure.walk",
        sleepMetricName: "Sleep Score",
        bins: sampleBins,
        totalSamples: 35,
        status: .valid,
        baseline: 85.0
    )
    
    BinAnalysisChartView(result: sampleResult)
        .padding()
}
