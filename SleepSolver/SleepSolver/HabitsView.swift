//
//  HabitsView.swift
//  SleepSolver
//
//  Created by Cade Christensen on 4/27/25.
//

import SwiftUI

// ADDED: Identifiable item for the sheet
struct DateSheetItem: Identifiable {
    let id = UUID()
    let date: Date
}

struct HabitsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var nightlySleepViewModel: NightlySleepViewModel
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var dateSheetItem: DateSheetItem? = nil
    @State private var dailyViewReloadTrigger = UUID() // ADDED: State for triggering DailyHabitsView reload
    @State private var isRefreshing = false // ADDED: Refresh state
    
    // ADDED: State to track whether habits can be added for the selected date
    @State private var canAddHabits: Bool = true

    // ADDED: DateFormatter for Month and Year
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy" // Format: e.g., "May 2025"
        return formatter
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) { // ZStack to overlay the button
                VStack(alignment: .center, spacing: 0) { // Main content VStack
                    // ADDED: Text view for Month and Year
                    Text(monthYearFormatter.string(from: selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top)

                    // Date Slider View
                    DateSliderView(selectedDate: $selectedDate)
                        .padding(.vertical, 5) // Add some vertical padding

                    // PageViewController
                    PageViewController(selectedDate: $selectedDate) { date in
                        // MODIFIED: Pass the dailyViewReloadTrigger and nightlySleepViewModel to DailyHabitsView
                        DailyHabitsView(date: date, context: viewContext, nightlySleepViewModel: nightlySleepViewModel, reloadTrigger: dailyViewReloadTrigger)
                    }
                    .id(dailyViewReloadTrigger) // MODIFIED: Force PageViewController reconstruction on trigger change
                }

                // Floating Action Button
                Button {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .full
                    dateFormatter.timeStyle = .none
                    print("HabitsView: '+' button tapped. Current selectedDate for sheet is: \(dateFormatter.string(from: selectedDate))")
                    
                    // Check if habits can be added for this date
                    if canAddHabits {
                        // MODIFIED: Set the identifiable item to trigger the sheet
                        self.dateSheetItem = DateSheetItem(date: selectedDate)
                    } else {
                        print("HabitsView: Cannot add habits for this date - no session available")
                        // TODO: Consider showing a toast or alert explaining why the button is disabled
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(canAddHabits ? .accentColor : .gray) // Dynamic color
                        .background(Color(.systemBackground)) // Add background for contrast
                        .clipShape(Circle())
                        .shadow(radius: canAddHabits ? 5 : 2) // Dynamic shadow
                        .opacity(canAddHabits ? 1.0 : 0.6) // Dynamic opacity
                }
                .disabled(!canAddHabits) // Disable when can't add habits
                .padding() // Add padding from the edges
            }
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await performHabitsRefresh()
                        }
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
        }
        .onAppear {
            // Check if habits can be added for the initial selected date
            updateCanAddHabits(for: selectedDate)
        }
        .onChange(of: selectedDate) { oldValue, newDate in
            // Update canAddHabits when date changes
            updateCanAddHabits(for: newDate)
        }
        // MODIFIED: Sheet modifier to use .sheet(item:content:) and add onDismiss
        .sheet(item: $dateSheetItem, onDismiss: {
            print("HabitSelectionView sheet dismissed. Updating dailyViewReloadTrigger.")
            dailyViewReloadTrigger = UUID() // Update the trigger on dismiss
        }) { item in
            HabitSelectionView(date: item.date)
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    // Refresh method for habits data - LOCAL ONLY (no sync)
    @MainActor
    private func performHabitsRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        print("[HabitsView] 🔄 Refresh button tapped - local refresh only")
        
        // Trigger reload of daily habits view (local data only)
        dailyViewReloadTrigger = UUID()
        
        // Add small delay for user feedback
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    // ADDED: Method to check if habits can be added for a given date
    private func updateCanAddHabits(for date: Date) {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        
        if isToday {
            // For today, habits can always be added
            canAddHabits = true
        } else {
            // For past days, check if there's a sleep session
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
                canAddHabits = false
                return
            }
            
            let session = nightlySleepViewModel.sleepSession(for: nextDay)
            canAddHabits = (session != nil && session?.habitMetrics != nil)
        }
    }
}

struct HabitsView_Previews: PreviewProvider {
    static var previews: some View {
        HabitsView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            // Provide dummy NightlySleepViewModel for PageViewController preview if needed by its structure (though ideally not)
            // .environmentObject(NightlySleepViewModel(context: PersistenceController.preview.container.viewContext))
    }
}
