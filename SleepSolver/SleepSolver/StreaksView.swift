//
//  StreaksView.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import SwiftUI
import CoreData

struct StreaksView: View {
    @StateObject private var viewModel: StreaksViewModel
    @Environment(\.managedObjectContext) private var viewContext
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: StreaksViewModel(context: context))
    }
    
    var body: some View {
        PremiumGate(feature: .streaks) {
            StreaksContentView(viewModel: viewModel)
        }
    }
}

struct StreaksContentView: View {
    @ObservedObject var viewModel: StreaksViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
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
                    
                    // Loading or Error State
                    if viewModel.isLoading {
                        ProgressView("Loading streaks...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let errorMessage = viewModel.errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            
                            Text("Error Loading Streaks")
                                .font(.headline)
                            
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                viewModel.loadStreakData()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if viewModel.streakData.isEmpty {
                        // Empty State
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            
                            Text("No Streak Data")
                                .font(.headline)
                            
                            Text("Start building streaks and see your personal records here!")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // Sectioned Streak Cards
                        LazyVStack(spacing: 20) {
                            if !viewModel.sleepStreaks.isEmpty {
                                StreakSection(title: "Sleep & Recovery", streaks: viewModel.sleepStreaks)
                            }
                            
                            if !viewModel.fitnessStreaks.isEmpty {
                                StreakSection(title: "Fitness & Activity", streaks: viewModel.fitnessStreaks)
                            }
                            
                            if !viewModel.habitStreaks.isEmpty {
                                StreakSection(title: "Daily Habits", streaks: viewModel.habitStreaks)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Streaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.loadStreakData()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .onAppear {
            if viewModel.streakData.isEmpty && !viewModel.isLoading {
                viewModel.loadStreakData()
            }
        }
    }
}

struct StreakCard: View {
    let streak: StreakData
    
    private var dayLabels: [String] {
        // Get current day of week (1 = Sunday, 2 = Monday, etc.)
        let today = Date()
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: today)
        
        // Start with standard labels (Sunday to Saturday)
        let standardLabels = ["S", "M", "T", "W", "T", "F", "S"]
        
        // Calculate the start index to make today the rightmost day
        // We want 7 days ending with today
        let startIndex = (todayWeekday - 7 + 7) % 7
        
        // Create rolling labels with today as the rightmost
        var rollingLabels: [String] = []
        for i in 0..<7 {
            let labelIndex = (startIndex + i) % 7
            rollingLabels.append(standardLabels[labelIndex])
        }
        
        return rollingLabels
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Row
            HStack {
                // Icon and Name
                HStack(spacing: 12) {
                    Image(systemName: streak.icon)
                        .font(.title2)
                        .foregroundColor(streak.bestStreak > 0 ? streak.color : .secondary)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(streak.name)
                            .font(.headline)
                            .foregroundColor(streak.bestStreak > 0 ? .primary : .secondary)
                        
                        if !streak.description.isEmpty {
                            Text(streak.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Best Streak (All-time record)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if streak.isNewRecord {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Text("\(streak.bestStreak)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(streak.bestStreak > 0 ? streak.color : .secondary)
                    }
                    
                    Text("best streak")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Weekly Progress Dots
            VStack(spacing: 8) {
                Text("Past 7 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        VStack(spacing: 6) {
                            Text(dayLabels[index])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Circle()
                                .fill(streak.dailyResults[index] ? streak.color : Color(.systemGray4))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(streak.dailyResults[index] ? Color.clear : Color(.systemGray3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(streak.isActive ? streak.color.opacity(0.3) : Color(.systemGray5), lineWidth: 1)
        )
    }
}

struct StreakSection: View {
    let title: String
    let streaks: [StreakData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(streaks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)
            
            // Streak Cards
            LazyVStack(spacing: 8) {
                ForEach(streaks) { streak in
                    StreakCard(streak: streak)
                }
            }
        }
    }
}

extension StreakType {
    var displayName: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .workout:
            return "Workout"
        case .habit:
            return "Habit"
        }
    }
}

struct StreaksView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        
        return StreaksView(context: context)
            .preferredColorScheme(.light)
    }
}
