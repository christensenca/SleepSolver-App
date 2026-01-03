import SwiftUI
import HealthKit
import CoreData
import Charts

struct NightlySleepView: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    @Environment(\.managedObjectContext) private var viewContext

    // Selected date is now primarily controlled by the PageViewController swipes
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isRefreshing = false
    @State private var refreshTrigger = UUID()
    
    // Phase 2: Use centralized sync coordinator
    @StateObject private var syncCoordinator = SleepDataSyncCoordinator.shared

    // ADDED: DateFormatter for Month and Year
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy" // Format: e.g., "May 2025"
        return formatter
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .center, spacing: 0) {
                    // ADDED: Text view for Month and Year
                    Text(monthYearFormatter.string(from: selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top)

                    // Date Slider View
                    DateSliderView(selectedDate: $selectedDate)
                        .padding(.vertical, 5)
                        .id(refreshTrigger) // Force refresh when refreshTrigger changes

                    // SWIPEABLE SUMMARY SECTION - Sleep Score & Recovery (changes with date slider)
                    PageViewController(selectedDate: $selectedDate) { date in
                        SleepSummarySection(selectedDate: date)
                    }
                    .environmentObject(viewModel)
                    .frame(height: 315) // Reduced height since we removed the additional metric cards

                    // FIXED TRENDS SECTION - Static 7-day trends (never changes)
                    TrendsSection()
                        .environmentObject(viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        performSleepRefresh()
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .onAppear {
                // DISCONNECTED: Comment out database refresh for migration
                // Only refresh cached data from CoreData, don't trigger HealthKit sync
                // Smart sync should only happen on app launch or explicit refresh button tap
                // viewModel.refreshCachedData(for: selectedDate)
                refreshTrigger = UUID()
            }
            // ADDED: Listen for sync completion to rebuild the cache and stop the refresh indicator
            .onReceive(NotificationCenter.default.publisher(for: .sleepDataSyncDidComplete)) { _ in
                print("[NightlySleepView] ✅ Received sleepDataSyncDidComplete notification. Rebuilding cache.")
                Task {
                    // Rebuild the ViewModel's cache with the latest data from CoreData
                    await viewModel.rebuildPersistentCache()
                    // Force the DateSliderView and other components to update
                    refreshTrigger = UUID()
                    // Stop the refresh indicator now that the sync and cache rebuild are complete
                    isRefreshing = false
                }
            }
        }
    }
    
    // RECONNECTED: Refresh method now triggers sync and relies on notifications for UI updates.
    @MainActor
    private func performSleepRefresh() {
        isRefreshing = true
        print("[NightlySleepView] 🔄 Refresh button tapped - triggering smart sync.")
        
        // Trigger smart sync via coordinator in a background Task.
        // The .onReceive handler will manage UI updates upon completion.
        Task {
            await syncCoordinator.requestSmartSync(priority: .userInitiated)
        }
    }
}

// MARK: - Sleep Summary Section (Swipeable, Changes with Date Slider)

struct SleepSummarySection: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    let selectedDate: Date
    @State private var animationTrigger = UUID()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // Use @FetchRequest-powered SleepMetricsCardView that observes Core Data directly
                SleepMetricsCardView(displayDate: selectedDate)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .id(animationTrigger) // Simple animation trigger
            }
        }
        .onAppear {
            print("[View] 📱 SleepSummarySection appeared for date: \(selectedDate)")
            // Trigger animation refresh
            animationTrigger = UUID()
        }
        .onChange(of: selectedDate) { _, newDate in
            print("[View] 📅 Date changed to: \(newDate)")
            // Force re-animation when date changes
            animationTrigger = UUID()
        }
        .onChange(of: viewModel.uiRefreshTrigger) { _, newTrigger in
            print("[View] 🔄 UI refresh trigger changed: \(newTrigger)")
            // Refresh when the view model triggers a UI update
            animationTrigger = UUID()
        }
    }
}

// MARK: - Trends Section (Fixed, Static 7-Day Trends)

struct TrendsSection: View {
    @EnvironmentObject var viewModel: NightlySleepViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // Header for trends
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sleep Trends")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top)
                }

                // Sleep Debt Chart - Cumulative Sleep Debt
                SleepDebtChartView()
                    .environmentObject(viewModel)

                // Sleep Stages Chart - REM + Deep Sleep
                SleepStagesChartView()
                    .environmentObject(viewModel)

                // Sleep Schedule Chart - Bedtime & Wake Time
                SleepScheduleChartView()
                    .environmentObject(viewModel)

                // Heart Rate & HRV Chart - Line plots with averages
                HeartRateHRVChartView()
                    .environmentObject(viewModel)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Chart Card View (Reusable Component)

struct ChartCardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
    }
}

// MARK: - Preview

struct NightlySleepView_Previews: PreviewProvider {
    static var previews: some View {
        // Use a Group to return multiple previews if needed, or just the main view
        // Ensure the environment setup is correct for the preview context
        let context = PersistenceController.preview.container.viewContext
        let hkManager = HealthKitManager.shared
        let nightlyVM = NightlySleepViewModel(context: context, healthKitManager: hkManager)

        // Simulate having some data for preview
        // let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        // nightlyVM.sleepSessions[Calendar.current.startOfDay(for: yesterday)] = nil // Example: No data yesterday
        // nightlyVM.sleepSessions[Calendar.current.startOfDay(for: Date())] = SleepSession(context: context) // Example: Dummy data today

        // Return the view directly, not wrapped in another type unless necessary
        NightlySleepView()
            .environment(\.managedObjectContext, context)
            .environmentObject(nightlyVM) // Provide the ViewModel
    }
}
