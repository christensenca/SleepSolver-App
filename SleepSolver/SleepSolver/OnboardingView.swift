import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingViewModel = OnboardingViewModel()
    @StateObject private var syncCoordinator = SleepDataSyncCoordinator.shared
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var isAuthorized: Bool? = nil
    @State private var showingAuthErrorAlert = false
    @State private var authErrorMessage = ""
    @State private var wasSyncing = false // To detect when sync finishes

    // ADD: State for current onboarding step
    @State private var currentStep: OnboardingStep = .initial

    // Enum for onboarding steps
    enum OnboardingStep {
        case initial
        case sleepNeed
        case completed
    }

    // REMOVED: init is no longer needed as the view model is self-contained.

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "moon.zzz.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.purple)

            Text("Welcome to SleepSolver")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Let's get your sleep history from HealthKit to get started.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Conditional content based on authorization and loading state
            if currentStep == .initial {
                initialStepView
            } else if currentStep == .sleepNeed {
                sleepNeedStepView
            }

            Spacer()
            Spacer()
        }
        .padding()
        .onAppear {
            // REMOVED: checkAuthorization() call.
            // We will now wait for the user to tap "Grant HealthKit Access".
            // isAuthorized remains nil initially.
        }
        .alert("HealthKit Authorization Failed", isPresented: $showingAuthErrorAlert) {
            Button("OK") { }
        } message: {
            Text(authErrorMessage)
        }
        // ADD: Listen to changes from the Sync Coordinator
        .onReceive(syncCoordinator.$isSyncing) { isSyncing in
            onboardingViewModel.isLoading = isSyncing

            // When syncing transitions from true to false, it means the sync has completed.
            if wasSyncing && !isSyncing {
                onboardingViewModel.completeLoading() // This now fetches from Core Data and calculates sleep need
                currentStep = .sleepNeed
            }
            wasSyncing = isSyncing
        }
        .onReceive(syncCoordinator.$syncProgress) { progress in
            onboardingViewModel.updateProgress(progress)
        }
        .onReceive(syncCoordinator.$syncStatus) { status in
            if let status = status {
                onboardingViewModel.updateStatus(status)
            }
        }
    }

    // MARK: - Step Views

    @ViewBuilder
    private var initialStepView: some View {
        // MODIFIED: Logic for initial view
        if isAuthorized == nil || isAuthorized == false {
            // Show "Grant HealthKit Access" if status is unknown (nil) or explicitly false (denied/error previously)
            Text("SleepSolver needs permission to access your sleep data from HealthKit.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Grant HealthKit Access") {
                requestAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
            .disabled(onboardingViewModel.isLoading)

        } else { // Authorized (isAuthorized == true)
            // Show loading progress or Get Started button
            if onboardingViewModel.isLoading {
                VStack {
                    Text(onboardingViewModel.loadingStatus ?? "Syncing with HealthKit...")
                        .font(.headline)
                    ProgressView(value: onboardingViewModel.progress)
                        .padding()
                    Text("This may take a few minutes for the initial sync.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let errorMessage = onboardingViewModel.errorMessage {
                Text("An error occurred: \(errorMessage)")
                    .foregroundColor(.red)
                Button("Retry") {
                    checkAndFetch()
                }
                .buttonStyle(.borderedProminent)
            } else {
                // This state is reached after authorization but before starting the fetch.
                Button("Begin Sync") {
                    checkAndFetch()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var sleepNeedStepView: some View {
        VStack(spacing: 20) {
            Text("Set Your Sleep Need")
                .font(.title2)
                .fontWeight(.bold)

            Text("Based on your history, your average sleep need is around \(formatTime(onboardingViewModel.recommendedTimeInBed)). Adjust below if needed.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Your selected sleep need: \(formatTime(onboardingViewModel.userSelectedSleepNeed))")
                .font(.headline)
                .padding(.bottom, 10)

            if onboardingViewModel.maxTimeInBed > onboardingViewModel.minTimeInBed {
                SleepNeedSliderView(
                    value: $onboardingViewModel.userSelectedSleepNeed,
                    range: onboardingViewModel.minTimeInBed...onboardingViewModel.maxTimeInBed,
                    step: 0.25
                )
                .padding(.horizontal)
            } else {
                Text("Not enough sleep data to determine a range. Using default values.")
                    .font(.caption)
                    .foregroundColor(.orange)
                Slider(value: $onboardingViewModel.userSelectedSleepNeed, in: 6...10, step: 0.25)
                    .disabled(true)
                    .padding(.horizontal)
            }
            
            Button("Save Sleep Need") {
                onboardingViewModel.saveUserSleepNeed()
                // Mark onboarding as complete
                hasCompletedOnboarding = true
                // Trigger a final sync to ensure the main view is up-to-date
                Task {
                    await syncCoordinator.requestOnboardingSync()
                }
                // currentStep = .completed // This line might be redundant if hasCompletedOnboarding drives the view change
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }

    // Helper to format time in hours to a readable string (e.g., "7.5 hours")
    private func formatTime(_ hours: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: hours)) ?? "N/A") hours"
    }

    // Function to check HealthKit authorization
    // This function is no longer called in .onAppear for the initial permission flow.
    // It could be used if you need to re-verify permissions at a later stage,
    // but ensure it's a passive check if called automatically.
    private func checkAuthorization() {
        // Use the shared HealthKitManager to check status
        HealthKitManager.shared.checkAuthorizationStatus { authorized in
            DispatchQueue.main.async {
                self.isAuthorized = authorized
            }
        }
    }

    // Function to request HealthKit authorization
    private func requestAuthorization() {
        onboardingViewModel.isLoading = true // Indicate activity while auth is in progress
        onboardingViewModel.updateStatus("Requesting HealthKit Permissions...")

        // Use the shared HealthKitManager to request authorization
        HealthKitManager.shared.requestAuthorization { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if success {
                    // Automatically start the sync process upon successful authorization
                    startFetch()
                } else {
                    self.onboardingViewModel.isLoading = false
                    self.authErrorMessage = error?.localizedDescription ?? "An unknown error occurred."
                    self.showingAuthErrorAlert = true
                }
            }
        }
    }

    // Function to check auth and then start fetch if authorized
    private func checkAndFetch() {
        // This function is called when the user taps "Begin Sync"
        // or "Retry" after authorization is granted.
        
        // It should trigger the full historical sync.
        Task {
            // MODIFIED: Call the new onboarding sync method for a full historical fetch
            await syncCoordinator.requestOnboardingSync()
        }
    }

    // Function to start the historical data fetch
    private func startFetch() {
        onboardingViewModel.startLoading()
        // Use the new SleepDataSyncCoordinator to perform the sync
        Task {
            await syncCoordinator.requestOnboardingSync()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview now only needs the context
        OnboardingView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
