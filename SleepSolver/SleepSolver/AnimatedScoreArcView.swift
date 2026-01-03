//
//  AnimatedScoreArcView.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import SwiftUI

struct AnimatedScoreArcView: View {
    let score: Double // 0-100
    let title: String
    let color: Color
    let size: CGFloat
    let animationKey: String // Unique key to force re-animation
    
    @State private var animatedProgress: Double = 0
    
    private var normalizedScore: Double {
        min(max(score, 0), 100) / 100.0
    }
    
    private var strokeWidth: CGFloat {
        size * 0.08 // Proportional to size
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.125, to: 0.875) // 3/4 circle starting from bottom
                    .stroke(
                        color.opacity(0.2),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90)) // Rotate to start from bottom
                    .frame(width: size, height: size)
                
                // Animated foreground arc
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
                
                // Score text in center
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", score))
                        .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(title)
                        .font(.system(size: size * 0.08, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
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
    VStack(spacing: 30) {
        HStack(spacing: 30) {
            AnimatedScoreArcView(
                score: 85,
                title: "Sleep Score",
                color: .blue,
                size: 120,
                animationKey: "preview1"
            )
            
            AnimatedScoreArcView(
                score: 72,
                title: "Recovery",
                color: .red,
                size: 120,
                animationKey: "preview2"
            )
        }
        
        AnimatedScoreArcView(
            score: 95,
            title: "Sleep Efficiency",
            color: .green,
            size: 80,
            animationKey: "preview3"
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
