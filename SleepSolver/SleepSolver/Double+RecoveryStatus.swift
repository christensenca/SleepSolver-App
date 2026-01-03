//
//  Double+RecoveryStatus.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import Foundation
import SwiftUI

extension Double {
    
    /// Converts a z-score to a recovery status string
    /// - Parameter isHigherBetter: Whether higher values are better for this metric
    /// - Returns: Status string ("optimal", "good", "attention", or "insufficient data")
    func recoveryStatusString(isHigherBetter: Bool = true) -> String {
        // Handle insufficient data case
        if self.isNaN {
            return "insufficient data"
        }
        
        let threshold: Double = 1.5  // ±1.5 std threshold
        
        if isHigherBetter {
            // For metrics where higher is better (HRV, SpO2)
            if self > threshold {
                return "optimal"      // Above +0.5 std
            } else if self >= -threshold {
                return "good"         // Within ±0.5 std
            } else {
                return "attention"    // Below -0.5 std
            }
        } else {
            // For metrics where lower is better (Temperature, RHR, Respiratory Rate)
            if self < -threshold {
                return "optimal"      // Below -0.5 std
            } else if self <= threshold {
                return "good"         // Within ±0.5 std
            } else {
                return "attention"    // Above +0.5 std
            }
        }
    }
    
    /// Converts a z-score to a recovery status enum for UI components
    /// - Parameter isHigherBetter: Whether higher values are better for this metric
    /// - Returns: RecoveryMetricStatus enum value
    func recoveryStatus(isHigherBetter: Bool = true) -> RecoveryMetricStatus {
        if self.isNaN {
            return .unknown
        }
        
        let statusString = self.recoveryStatusString(isHigherBetter: isHigherBetter)
        return RecoveryMetricStatus.from(string: statusString)
    }
    
    /// Converts a z-score to a color for UI display
    /// - Parameter isHigherBetter: Whether higher values are better for this metric
    /// - Returns: SwiftUI Color based on the recovery status
    func recoveryColor(isHigherBetter: Bool = true) -> Color {
        return self.recoveryStatus(isHigherBetter: isHigherBetter).color
    }
    
    /// Returns a formatted string representation of the z-score for display
    var formattedZScore: String {
        if self.isNaN {
            return "N/A"
        }
        return String(format: "%.2f", self)
    }
}

/// Enum for different penalty directions used in flexible z-score calculations
enum RecoveryPenalizeDirection {
    case aboveBaseline  // Penalize when above baseline (e.g., respiratory rate)
    case belowBaseline  // Penalize when below baseline (e.g., SpO2)
    
    /// Interprets a raw z-score based on the penalty direction
    /// - Parameter zScore: The raw z-score (positive = above baseline, negative = below baseline)
    /// - Returns: Adjusted z-score for status interpretation
    func interpretZScore(_ zScore: Double) -> Double {
        if zScore.isNaN { return zScore }
        
        switch self {
        case .aboveBaseline:
            // For metrics like respiratory rate, being above baseline is bad
            return zScore > 0 ? abs(zScore) : -abs(zScore) // Positive becomes penalty, negative stays good
        case .belowBaseline:
            // For metrics like SpO2, being below baseline is bad
            return zScore < 0 ? abs(zScore) : -abs(zScore) // Negative becomes penalty, positive stays good
        }
    }
}

extension Double {
    /// Converts a flexible z-score to a recovery status string
    /// - Parameter penalizeDirection: The direction that should be penalized
    /// - Returns: Status string based on flexible interpretation
    func flexibleRecoveryStatusString(penalizeDirection: RecoveryPenalizeDirection) -> String {
        if self.isNaN {
            return "insufficient data"
        }
        
        let interpretedZScore = penalizeDirection.interpretZScore(self)
        return interpretedZScore.recoveryStatusString()
    }
    
    /// Converts a flexible z-score to a recovery status enum
    /// - Parameter penalizeDirection: The direction that should be penalized
    /// - Returns: RecoveryMetricStatus enum value
    func flexibleRecoveryStatus(penalizeDirection: RecoveryPenalizeDirection) -> RecoveryMetricStatus {
        if self.isNaN {
            return .unknown
        }
        
        let statusString = self.flexibleRecoveryStatusString(penalizeDirection: penalizeDirection)
        return RecoveryMetricStatus.from(string: statusString)
    }
}
