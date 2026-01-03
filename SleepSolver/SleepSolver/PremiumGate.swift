//
//  PremiumGate.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import SwiftUI

struct PremiumGate<Content: View>: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    let feature: PremiumFeature
    let content: () -> Content
    
    var body: some View {
        Group {
            if subscriptionManager.isPremium {
                // User has premium access - show content
                content()
            } else {
                // User needs premium - show detailed paywall directly
                PaywallView(feature: feature)
                    .environmentObject(subscriptionManager)
            }
        }
        .onAppear {
            // Check subscription status when view appears
            Task {
                await subscriptionManager.updateSubscriptionStatus()
            }
        }
    }
}

struct PremiumLockedView: View {
    let feature: PremiumFeature
    let onUpgradeTapped: () -> Void
    
    var body: some View {
        ZStack {
            // Blurred background content preview
            VStack {
                // Mock content to show what's behind the paywall
                PreviewContent(feature: feature)
            }
            .blur(radius: 8)
            .opacity(0.3)
            
            // Overlay with upgrade prompt
            VStack(spacing: 24) {
                Spacer()
                
                // Premium icon and message
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Premium Feature")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(feature.unlockMessage)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // Upgrade button
                Button(action: onUpgradeTapped) {
                    HStack {
                        Image(systemName: "crown.fill")
                        Text("Start 7-Day Free Trial")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                // Trial info
                Text("Free for 7 days, then $4.99/month")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .background(Color(.systemBackground).opacity(0.95))
        }
    }
}

struct PreviewContent: View {
    let feature: PremiumFeature
    
    var body: some View {
        switch feature {
        case .streaks:
            StreaksPreviewContent()
        case .correlations:
            CorrelationsPreviewContent()
        }
    }
}

struct StreaksPreviewContent: View {
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly Streaks")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your best streaks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            // Mock streak cards
            VStack(spacing: 16) {
                MockStreakCard(
                    title: "Sleep & Recovery",
                    streaks: [
                        ("8+ Hours Sleep", "7", .blue),
                        ("Consistent Bedtime", "12", .green)
                    ]
                )
                
                MockStreakCard(
                    title: "Fitness & Activity",
                    streaks: [
                        ("Daily Exercise", "5", .orange),
                        ("10k Steps", "9", .red)
                    ]
                )
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
}

struct CorrelationsPreviewContent: View {
    var body: some View {
        VStack(spacing: 20) {
            // Header section
            VStack(spacing: 12) {
                HStack {
                    Text("Time window:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                // Mock segmented control
                HStack {
                    Text("1 Week")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    
                    Text("1 Month")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                    
                    Text("3 Months")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            
            // Mock charts
            VStack(spacing: 16) {
                MockCorrelationChart(title: "Exercise Impact on Sleep Quality", correlation: "+15%")
                MockCorrelationChart(title: "Screen Time Impact on Sleep Duration", correlation: "-8%")
                MockCorrelationChart(title: "Caffeine Impact on Sleep Onset", correlation: "-22%")
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
}

struct MockStreakCard: View {
    let title: String
    let streaks: [(String, String, Color)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                ForEach(streaks.indices, id: \.self) { index in
                    let streak = streaks[index]
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(streak.2)
                        
                        Text(streak.0)
                            .font(.headline)
                        
                        Spacer()
                        
                        Text(streak.1)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(streak.2)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
}

struct MockCorrelationChart: View {
    let title: String
    let correlation: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(correlation)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(correlation.hasPrefix("+") ? .green : .red)
            }
            
            // Mock bar chart
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<7) { _ in
                    Rectangle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 24, height: CGFloat.random(in: 20...60))
                        .cornerRadius(2)
                }
            }
            .frame(height: 60)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct PremiumGate_Previews: PreviewProvider {
    static var previews: some View {
        PremiumGate(feature: .streaks) {
            Text("Premium Content")
        }
        .environmentObject(SubscriptionManager.shared)
    }
}
