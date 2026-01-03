//
//  UnifiedScoreArcView.swift
//  SleepSolver
//
//  Created by GitHub Copilot on 5/24/25.
//

import SwiftUI

enum ScoreType {
    case sleep
}

struct UnifiedScoreArcView: View {
    let sessionV2: SleepSessionV2?
    let scoreType: ScoreType
    let title: String
    let color: Color
    let size: CGFloat
    let animationKey: String
    
    init(sessionV2: SleepSessionV2?, scoreType: ScoreType, title: String, color: Color, size: CGFloat, animationKey: String) {
        self.sessionV2 = sessionV2
        self.scoreType = scoreType
        self.title = title
        self.color = color
        self.size = size
        self.animationKey = animationKey
    }
    
    private var isValid: Bool {
        guard let sessionV2 = sessionV2 else { return false }
        return sessionV2.sleepScore > 0
    }
    
    private var displayValue: String {
        if !isValid {
            return "--"
        }
        
        guard let sessionV2 = sessionV2 else { return "--" }
        
        return String(Int(sessionV2.sleepScore))
    }
    
    private var score: Double {
        if isValid, let sessionV2 = sessionV2 {
            return Double(sessionV2.sleepScore)
        }
        return 0 // Use 0 for animation when invalid
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.125, to: 0.875) // 3/4 circle starting from bottom
                    .stroke(
                        isValid ? color.opacity(0.2) : Color.gray.opacity(0.2),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90)) // Rotate to start from bottom
                    .frame(width: size, height: size)
                
                // Animated foreground arc (only show if valid)
                if isValid {
                    AnimatedArcView(
                        score: score,
                        color: color,
                        size: size,
                        strokeWidth: strokeWidth,
                        animationKey: animationKey
                    )
                }
                
                // Score text in center
                VStack(spacing: 2) {
                    Text(displayValue)
                        .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                        .foregroundColor(isValid ? .primary : .secondary)
                    
                    Text(title)
                        .font(.system(size: size * 0.08, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private var strokeWidth: CGFloat {
        size * 0.08 // Proportional to size
    }
}

// Helper view for the animated arc portion
struct AnimatedArcView: View {
    let score: Double
    let color: Color
    let size: CGFloat
    let strokeWidth: CGFloat
    let animationKey: String
    
    @State private var animatedProgress: Double = 0
    
    private var normalizedScore: Double {
        min(max(score, 0), 100) / 100.0
    }
    
    var body: some View {
        Circle()
            .trim(from: 0.125, to: 0.125 + (0.75 * animatedProgress)) // Fill based on animated progress
            .stroke(
                LinearGradient(
                    colors: [color.opacity(0.7), color],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(90)) // Rotate to start from bottom
            .frame(width: size, height: size)
            .onAppear {
                startAnimation()
            }
            .onChange(of: animationKey) { _, _ in
                // Re-animate whenever the animation key changes
                startAnimation()
            }
            .onChange(of: score) { _, _ in
                // Re-animate when score changes
                startAnimation()
            }
    }
    
    private func startAnimation() {
        // Always reset to 0 first
        animatedProgress = 0
        
        // Start animation with a small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 1.5)) {
                animatedProgress = normalizedScore
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.container.viewContext
    
    // Valid session
    let validSessionV2 = SleepSessionV2(context: context)
    validSessionV2.sleepScore = 85
    validSessionV2.totalTimeInBed = 8.5 * 3600
    validSessionV2.totalSleepTime = 7.8 * 3600
    validSessionV2.isFinalized = true  // Make sure recovery data is shown
    validSessionV2.hrvStatus = 0.3      // Optimal z-score (within ±0.5 std)
    validSessionV2.rhrStatus = -0.7     // Good z-score (within ±1.0 std)
    validSessionV2.temperatureStatus = 1.2  // Attention z-score (beyond ±1.0 std)
    validSessionV2.respStatus = 0.4     // Optimal z-score (flexible interpretation)
    validSessionV2.spo2Status = -0.8    // Good z-score (flexible interpretation)

    // Invalid session (no sleep data)
    let invalidSessionV2 = SleepSessionV2(context: context)
    invalidSessionV2.sleepScore = 0
    invalidSessionV2.totalTimeInBed = 0
    invalidSessionV2.totalSleepTime = 0
    invalidSessionV2.isFinalized = false  // Not finalized, so recovery data won't show
    
    return ScrollView {
        VStack(spacing: 30) {
            Text("Sleep Score")
                .font(.headline)
            
            UnifiedScoreArcView(
                sessionV2: validSessionV2,
                scoreType: .sleep,
                title: "Sleep Score",
                color: .blue,
                size: 150,
                animationKey: "preview-valid-sleep"
            )
            
            // --- NEW RECOVERY METRICS MOCK-UP ---
            RecoveryMetricsView(session: validSessionV2)
            
            Text("Invalid Session (No Data)")
                .font(.headline)
            
            UnifiedScoreArcView(
                sessionV2: invalidSessionV2,
                scoreType: .sleep,
                title: "Sleep Score",
                color: .blue,
                size: 150,
                animationKey: "preview-invalid-sleep"
            )
            
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
