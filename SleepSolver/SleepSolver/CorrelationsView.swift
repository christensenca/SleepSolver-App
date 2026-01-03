//
//  CorrelationsView.swift
//  SleepSolver
//
//  Created by Cade Christensen on 4/27/25.
//

import SwiftUI
import Charts

struct CorrelationsView: View {
    // Inject the managed object context
    @Environment(\.managedObjectContext) private var viewContext
    
    @ObservedObject var viewModel: CorrelationsViewModel
    @EnvironmentObject var nightlySleepViewModel: NightlySleepViewModel
    
    var body: some View {
        PremiumGate(feature: .correlations) {
            CorrelationsContentView(viewModel: viewModel, nightlySleepViewModel: nightlySleepViewModel)
        }
    }
}

struct CorrelationsContentView: View {
    @ObservedObject var viewModel: CorrelationsViewModel
    @ObservedObject var nightlySleepViewModel: NightlySleepViewModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Clean header
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("Sleep Correlations")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Text("Discover how your habits impact sleep quality")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                .background(Color(.systemBackground))
                
                Divider()
                
                // Content section
                if viewModel.isLoading {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Show skeleton cards while loading
                            ForEach(0..<5) { _ in
                                                                            CorrelationCardView(insight: nil)
                                    .redacted(reason: .placeholder)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    VStack(spacing: 16) {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            Task {
                                viewModel.calculateAllRegressionInsights()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Show baseline progress card if building baseline
                            if let progress = viewModel.baselineProgress {
                                VStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chart.bar.fill")
                                            .foregroundColor(.blue)
                                            .font(.title2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Building Baseline")
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("Need \(progress.required - progress.current) more days of data")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    
                                    ProgressView(value: Double(progress.current), total: Double(progress.required))
                                        .progressViewStyle(.linear)
                                        .tint(.blue)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                                .padding(.horizontal)
                                
                                // Show placeholder cards below (grouped by sleep metric)
                                ForEach(CorrelationMetric.allCases.prefix(3)) { metric in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 8) {
                                            Image(systemName: metric.icon)
                                                .foregroundColor(.blue.opacity(0.3))
                                                .font(.title3)
                                            Text(metric.displayName)
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary.opacity(0.3))
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                        
                                        // Show 2-3 placeholder cards per group
                                        ForEach(0..<2) { _ in
                                            CorrelationCardView(insight: nil)
                                                .opacity(0.3)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            } else {
                                // Show grouped correlation cards by sleep metric
                                if viewModel.sleepMetricGroups.isEmpty {
                                    VStack(spacing: 16) {
                                        VStack(spacing: 8) {
                                            Text("No significant correlations found")
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("Try adjusting your filters or check back later")
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .padding()
                                    }
                                } else {
                                    ForEach(viewModel.sleepMetricGroups) { group in
                                        // Sleep metric section header
                                        VStack(alignment: .leading, spacing: 12) {
                                            HStack(spacing: 8) {
                                                Image(systemName: group.sleepMetric.icon)
                                                    .foregroundColor(.blue)
                                                    .font(.title3)
                                                Text(group.sleepMetric.displayName)
                                                    .font(.title3)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if !group.additionalInsights.isEmpty {
                                                    Text("\(group.allInsights.count) insights")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(.horizontal)
                                            
                                            // Top insights (always visible)
                                            ForEach(group.topInsights) { insight in
                                                CorrelationCardView(insight: insight)
                                                    .padding(.horizontal)
                                            }
                                            
                                            // Additional insights (expandable)
                                            if !group.additionalInsights.isEmpty {
                                                VStack(spacing: 8) {
                                                    Button(action: {
                                                        viewModel.toggleGroupExpansion(group.id)
                                                    }) {
                                                        HStack {
                                                            Text(group.isExpanded ? "Show less" : "Show \(group.additionalInsights.count) more")
                                                                .font(.subheadline)
                                                                .foregroundColor(.blue)
                                                            Spacer()
                                                            Image(systemName: group.isExpanded ? "chevron.up" : "chevron.down")
                                                                .foregroundColor(.blue)
                                                                .font(.caption)
                                                        }
                                                        .padding(.horizontal)
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                    
                                                    if group.isExpanded {
                                                        ForEach(group.additionalInsights) { insight in
                                                            CorrelationCardView(insight: insight)
                                                                .padding(.horizontal)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            viewModel.calculateAllRegressionInsights()
                        }
                    } label: {
                        if viewModel.regressionInsights.isEmpty && viewModel.baselineProgress == nil {
                            Text("Analyze")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                // Calculate correlations when the view appears if no data and not building baseline
                if viewModel.regressionInsights.isEmpty && !viewModel.isLoading && viewModel.baselineProgress == nil {
                    Task {
                        viewModel.calculateAllRegressionInsights()
                    }
                }
            }
        }
    }
    
    /// Helper function to get the icon for health metrics
    private func iconForHealthMetric(_ metricName: String) -> String {
        switch metricName {
        case "Exercise Time":
            return "figure.run"
        case "Steps":
            return "figure.walk"
        case "Time in Daylight":
            return "sun.max.fill"
        default:
            return "chart.bar"
        }
    }
}

/// View for displaying individual regression results as cards
struct CorrelationCardView: View {
    let insight: RegressionInsight?
    
    var body: some View {
        if let insight = insight {
            NavigationLink(destination: BinAnalysisChartView(result: insight.binAnalysisResult ?? BinAnalysisResult(
                healthMetricName: insight.healthMetricName,
                healthMetricIcon: insight.healthMetricIcon,
                sleepMetricName: insight.sleepMetricName,
                bins: [],
                totalSamples: 1, // Show at least 1 to avoid "0 of 7" confusion
                status: .insufficientData(current: 1, required: 7),
                baseline: 0.0
            ))) {
                VStack(alignment: .leading, spacing: 12) {
                    // Header with icons and names
                    HStack(spacing: 8) {
                        Image(systemName: insight.healthMetricIcon)
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.healthMetricName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: insight.sleepMetricIcon)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text("→ \(insight.sleepMetricName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Impact description
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(insight.impactDescription)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(insight.absoluteImpact >= 0 ? .green : .red)
                                .multilineTextAlignment(.trailing)
                            
                            // Confidence level indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(insight.confidenceLevel.color)
                                    .frame(width: 8, height: 8)
                                Text(insight.confidenceLevel.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("\(insight.sampleSize) obs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Tap hint
                    HStack {
                        Spacer()
                        Text("Tap for details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            // Skeleton/placeholder version
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 16)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 12)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 20)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 70, height: 12)
                    }
                }
                
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 12)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

/// Custom toggle style that renders as a checkbox
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .blue : .gray)
                    .font(.system(size: 16))
                
                configuration.label
                    .foregroundColor(.primary)
                
                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CorrelationsView_Previews: PreviewProvider {
    static var previews: some View {
        // Create dummy context for preview
        let context = PersistenceController.preview.container.viewContext
        let viewModel = CorrelationsViewModel(context: context)

        CorrelationsView(viewModel: viewModel)
            .environment(\.managedObjectContext, context)
    }
}
