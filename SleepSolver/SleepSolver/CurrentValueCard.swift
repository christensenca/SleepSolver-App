//
//  CurrentValueCard.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import SwiftUI

struct CurrentValueCard: View {
    let title: String
    let value: Double
    let unit: String
    let iconName: String
    
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
                    
                    Text("Current value only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Current value display
                    if unit == "°F" {
                        Text(formatTemperatureValue(value, unit: unit))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    } else {
                        Text(String(format: "%.1f %@", value, unit))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Text("No baseline data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // Format temperature to 2 significant figures (same as RecoveryComponentCard)
    private func formatTemperatureValue(_ value: Double, unit: String) -> String {
        if value >= 100 {
            return String(format: "%.0f %@", value, unit)  // e.g., "102°F"
        } else {
            return String(format: "%.1f %@", value, unit)  // e.g., "96.8°F"
        }
    }
}

struct CurrentValueCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 15) {
            CurrentValueCard(
                title: "Heart Rate Variability",
                value: 42.5,
                unit: "ms",
                iconName: "waveform.path.ecg.rectangle.fill"
            )
            
            CurrentValueCard(
                title: "Resting Heart Rate",
                value: 58.0,
                unit: "bpm",
                iconName: "heart.fill"
            )
            
            CurrentValueCard(
                title: "Sleep Temperature",
                value: 96.8,
                unit: "°F",
                iconName: "thermometer"
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
