import SwiftUI

struct ContentView: View {
    // Access the shared ViewModel from the environment
    @EnvironmentObject var nightlySleepViewModel: NightlySleepViewModel
    @Environment(\.managedObjectContext) private var viewContext
    
    // Create the correlations view model
    @StateObject private var correlationsViewModel = CorrelationsViewModel(context: PersistenceController.shared.container.viewContext)

    var body: some View {
        TabView {
            // Pass the environment object down if needed, or views can access it directly
            NightlySleepView()
                .tabItem {
                    Label("Sleep", systemImage: "moon.zzz.fill")
                }

            // Use HabitsView directly for the Habits tab
            HabitsView()
                .tabItem {
                    Label("Habits", systemImage: "figure.walk")
                }
                .environment(\.managedObjectContext, viewContext) // Pass context

            StreaksView(context: viewContext)
                .tabItem {
                    Label("Streaks", systemImage: "calendar.badge.checkmark")
                }

            CorrelationsView(viewModel: correlationsViewModel)
                .tabItem {
                    Label("Correlations", systemImage: "chart.xyaxis.line")
                }
                .environment(\.managedObjectContext, viewContext) // Pass context if needed
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        // The EnvironmentObject is available to all child views of ContentView
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // Create dummy data/context for preview
        let context = PersistenceController.preview.container.viewContext
        let hkManager = HealthKitManager.shared
        let nightlyVM = NightlySleepViewModel(context: context, healthKitManager: hkManager)

        ContentView()
            .environment(\.managedObjectContext, context)
            .environmentObject(nightlyVM) // Provide the ViewModel for the preview
    }
}
