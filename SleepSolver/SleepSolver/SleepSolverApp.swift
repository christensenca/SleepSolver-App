//
//  SleepSolverApp.swift
//  SleepSolver
//
//  Created by Cade Christensen on 4/27/25.
//

import SwiftUI

@main
struct SleepSolverApp: App {
    // Keep static properties
    static let persistenceController = PersistenceController.shared
    static let healthKitManager = HealthKitManager.shared

    // Create a single instance of NightlySleepViewModel to share
    @StateObject var nightlySleepViewModel: NightlySleepViewModel
    
    // Add SubscriptionManager to the environment
    @StateObject var subscriptionManager = SubscriptionManager.shared

    // ADD: AppStorage to track onboarding completion
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // ADD: Environment variable for scene phase
    @Environment(\.scenePhase) private var scenePhase

    // Static factory method now uses static properties
    private static func createNightlySleepViewModel() -> NightlySleepViewModel {
        // Access static properties directly
        let context = Self.persistenceController.container.viewContext
        let manager = Self.healthKitManager
        return NightlySleepViewModel(context: context, healthKitManager: manager)
    }

    init() {
        // Initialize the StateObject using the static factory method
        _nightlySleepViewModel = StateObject(wrappedValue: Self.createNightlySleepViewModel())
    }

    var body: some Scene {
        WindowGroup {
            // Use the static property directly for the environment
            let viewContext = Self.persistenceController.container.viewContext
            // Check onboarding status
            if hasCompletedOnboarding {
                ContentView()
                    .environment(\.managedObjectContext, viewContext)
                    // Pass the shared ViewModel to ContentView and its children
                    .environmentObject(nightlySleepViewModel)
                    .environmentObject(subscriptionManager)
                    .preferredColorScheme(.dark)
            } else {
                // Show OnboardingView if onboarding is not complete
                OnboardingView()
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(subscriptionManager)
                    .preferredColorScheme(.dark)
            }
        }
        // ADD: onChange modifier to handle scene phase changes
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Only attempt HealthKit authorization and sync if onboarding is complete
                if hasCompletedOnboarding {
                    print("[App] 🚀 Scene became active and onboarding is complete. Using unified sync coordinator.")
                    // Ensure HealthKit authorization before syncing
                    Self.healthKitManager.requestAuthorization { authorized, error in
                        if authorized {
                            print("[App] ✅ HealthKit authorized. Requesting smart sync via coordinator.")
                            // Use unified sync coordinator for app launch sync
                            Task {
                                await SleepDataSyncCoordinator.shared.requestAppLaunchSync()
                            }
                        } else {
                            if let anError = error {
                                print("[App] ❌ HealthKit authorization failed: \(anError.localizedDescription)")
                            } else {
                                print("[App] ❌ HealthKit authorization denied or not determined.")
                            }
                        }
                    }
                } else {
                    print("[App] ⏸️ Scene became active, but onboarding is not yet complete. Skipping automatic sync.")
                }
            }
        }
    }
}
