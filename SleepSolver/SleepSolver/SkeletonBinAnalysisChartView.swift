//
//  SkeletonBinAnalysisChartView.swift
//  SleepSolver
//
//  Created by Cade Christensen on 8/2/25.
//

import SwiftUI
import Charts

struct SkeletonBinAnalysisChartView: View {
    let healthMetricName: String
    let healthMetricIcon: String
    let insufficientDataMessage: String?
    let currentDataCount: Int
    let requiredDataCount: Int
    
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header matching real chart
            HStack {
                Image(systemName: healthMetricIcon)
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(healthMetricName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let message = insufficientDataMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Need \(requiredDataCount - currentDataCount) more days of data")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                // Data status indicator
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(currentDataCount)/\(requiredDataCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: Double(currentDataCount), total: Double(requiredDataCount))
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                        .tint(.orange)
                }
            }
            
            // Skeleton chart
            Chart {
                // Create placeholder bars
                ForEach(0..<4, id: \.self) { index in
                    BarMark(
                        x: .value("Range", getPlaceholderLabel(for: index, metric: healthMetricName)),
                        y: .value("Value", getPlaceholderHeight(for: index))
                    )
                    .foregroundStyle(.gray.opacity(0.3))
                    .cornerRadius(4)
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            // Removed shimmer effect to prevent flashing - can be re-enabled later if needed
            // .overlay(
            //     // Subtle shimmer effect
            //     Rectangle()
            //         .fill(
            //             LinearGradient(
            //                 colors: [.clear, .gray.opacity(0.1), .clear],
            //                 startPoint: .leading,
            //                 endPoint: .trailing
            //             )
            //         )
            //         .frame(width: 80)
            //         .offset(x: shimmerOffset)
            //         .clipped()
            // )
            // .onAppear {
            //     withAnimation(
            //         .easeInOut(duration: 2.0)
            //         .repeatForever(autoreverses: false)
            //     ) {
            //         shimmerOffset = 250
            //     }
            // }
            
            // Helpful message
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.caption)
                
                Text("This chart will show how \(healthMetricName.lowercased()) affects your sleep once you have enough data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private func getPlaceholderLabel(for index: Int, metric: String) -> String {
        switch metric {
        case "Exercise Time":
            return ["0-30 min", "30-60 min", "60-90 min", "90+ min"][index]
        case "Steps":
            return ["0-5K", "5K-8K", "8K-12K", "12K+"][index]
        case "Time in Daylight":
            return ["0-60 min", "60-120 min", "120-180 min", "180+ min"][index]
        default:
            return ["Low", "Medium", "High", "Very High"][index]
        }
    }
    
    private func getPlaceholderHeight(for index: Int) -> Double {
        // Create varied heights for visual interest
        let heights = [65.0, 78.0, 72.0, 85.0]
        return heights[index]
    }
}

struct SkeletonBinAnalysisChartView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SkeletonBinAnalysisChartView(
                healthMetricName: "Exercise Time",
                healthMetricIcon: "figure.run",
                insufficientDataMessage: nil,
                currentDataCount: 3,
                requiredDataCount: 7
            )
            
            SkeletonBinAnalysisChartView(
                healthMetricName: "Steps",
                healthMetricIcon: "figure.walk",
                insufficientDataMessage: "Need consistent step tracking",
                currentDataCount: 1,
                requiredDataCount: 7
            )
        }
        .padding()
    }
}
