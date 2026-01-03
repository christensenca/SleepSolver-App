import Foundation
import Combine
import CoreData
import HealthKit // Required for HKQuantityTypeIdentifier

class OnboardingViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var errorMessage: String? = nil
    @Published var loadingStatus: String? = nil // e.g., "Fetching data for May 2025..."

    // MARK: - Sleep Need Properties
    @Published var minTimeInBed: Double = 0.0 // In hours
    @Published var maxTimeInBed: Double = 0.0 // In hours
    @Published var recommendedTimeInBed: Double = 0.0 // 75th percentile, in hours
    @Published var userSelectedSleepNeed: Double = 0.0 // In hours

    private var cancellables = Set<AnyCancellable>()

    func startLoading() {
        isLoading = true
        progress = 0.0
        errorMessage = nil
        loadingStatus = "Preparing to fetch data..."
    }

    func updateProgress(_ newProgress: Double) {
        progress = max(0.0, min(1.0, newProgress)) // Clamp progress between 0 and 1
    }

    func updateStatus(_ newStatus: String) {
        loadingStatus = newStatus
    }

    func setError(_ message: String) {
        isLoading = false
        errorMessage = message
        loadingStatus = nil
    }

    // MODIFIED: completeLoading no longer accepts sleep data directly.
    // It now fetches the processed SleepSessionV2 data from Core Data.
    func completeLoading() {
        self.loadingStatus = "Sync complete! Calculating sleep need..."

        // Now that sync is done, fetch the last 6 months of sessions from Core Data
        fetchSleepSessionsFromCoreData {
            self.isLoading = false
            self.progress = 1.0
            self.loadingStatus = "Sleep need calculated. Ready to proceed."
        }
    }

    // NEW: Fetches SleepSessionV2 from Core Data and calculates sleep need.
    private func fetchSleepSessionsFromCoreData(completion: @escaping () -> Void) {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()

        // Fetch sessions from the last 6 months to calculate sleep need
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -6, to: endDate) else {
            setError("Could not determine date range for sleep need calculation.")
            completion()
            return
        }

        fetchRequest.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay <= %@", startDate as CVarArg, endDate as CVarArg)

        context.perform {
            do {
                let sessions = try context.fetch(fetchRequest)
                print("[OnboardingViewModel] Fetched \(sessions.count) SleepSessionV2 entities for sleep need calculation.")
                // Pass the fetched sessions to the calculation function
                self.calculateSleepNeedValues(sessions: sessions)
            } catch {
                self.setError("Failed to fetch sleep sessions from the database: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    // MARK: - Sleep Need Calculation
    // MODIFIED: Now accepts an array of SleepSessionV2 objects
    func calculateSleepNeedValues(sessions: [SleepSessionV2]) { // Expecting sleep data in hours
        // Extract total sleep time in hours from each session
        let sleepData = sessions.map { $0.totalSleepTime / 3600.0 }

        // For example, if sleepData is an array of 'time in bed' samples in hours
        if sleepData.isEmpty {
            // Default values if no data is available
            minTimeInBed = 6.0
            maxTimeInBed = 10.0
            recommendedTimeInBed = 8.0
            userSelectedSleepNeed = 8.0 // Initialize with recommended
            return
        }

        let sortedSleepData = sleepData.sorted()
        minTimeInBed = sortedSleepData.first ?? 6.0
        maxTimeInBed = sortedSleepData.last ?? 10.0

        // Calculate median
        let count = sortedSleepData.count
        var median: Double
        if count % 2 == 0 {
            // Even number of elements, average of the two middle elements
            median = (sortedSleepData[count / 2 - 1] + sortedSleepData[count / 2]) / 2.0
        } else {
            // Odd number of elements, the middle element
            median = sortedSleepData[count / 2]
        }

        // Round median up to the nearest half hour
        recommendedTimeInBed = ceil(median * 2.0) / 2.0
        
        userSelectedSleepNeed = recommendedTimeInBed // Initialize with recommended
        print("[OnboardingViewModel] Calculated sleep need: Recommended = \(recommendedTimeInBed)h, User Initial = \(userSelectedSleepNeed)h")
    }

    // MARK: - Save Sleep Need
    func saveUserSleepNeed() {
        UserDefaults.standard.set(userSelectedSleepNeed, forKey: "userSleepNeed")
        print("User sleep need saved: \\(userSelectedSleepNeed) hours")
    }
}
