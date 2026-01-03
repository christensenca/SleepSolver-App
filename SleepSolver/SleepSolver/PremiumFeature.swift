//
//  PremiumFeature.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import Foundation

// MARK: - Supporting Types

enum PremiumFeature {
    case streaks
    case correlations
    
    var unlockMessage: String {
        switch self {
        case .streaks:
            return "Track your daily habits and build powerful streaks"
        case .correlations:
            return "Discover how your habits impact your sleep quality"
        }
    }
    
    var primaryBenefit: String {
        switch self {
        case .streaks:
            return "Habit Streaks"
        case .correlations:
            return "Sleep Correlations"
        }
    }
    
    static let allBenefits: [FeatureBenefit] = [
        FeatureBenefit(
            icon: "chart.line.uptrend.xyaxis",
            title: "Sleep Correlations",
            description: "Analyze how your daily habits affect sleep quality and recovery"
        ),
        FeatureBenefit(
            icon: "flame.fill",
            title: "Habit Streaks",
            description: "Track daily habits and build momentum with streak tracking"
        )
    ]
}

struct FeatureBenefit {
    let icon: String
    let title: String
    let description: String
}
