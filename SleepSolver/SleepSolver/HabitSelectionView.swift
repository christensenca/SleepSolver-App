import SwiftUI
import CoreData

struct HabitSelectionView: View {
    let date: Date
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // Update FetchRequest to filter out archived habits AND HealthKit metrics
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \HabitDefinition.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \HabitDefinition.name, ascending: true)
        ],
        // Only show non-archived manual habits (all HabitDefinitions are now manual)
        predicate: NSPredicate(format: "isArchived == NO")
    ) private var habitDefinitions: FetchedResults<HabitDefinition>

    // State for custom habit sheet
    @State private var showingCustomHabitSheet = false

    // State for duplicate alert
    @State private var showingDuplicateAlert = false
    @State private var duplicateHabitName: String = ""

    var body: some View {
        // Embed the List within a NavigationView to allow navigation
        NavigationView {
            List {
                Section("Select Habit") {
                    // Iterate over fetched HabitDefinitions
                    ForEach(habitDefinitions) { definition in
                        Button {
                            // Use definition's name and icon
                            saveHabit(name: definition.name, icon: definition.icon)
                        } label: {
                            HStack {
                                // Use the updated iconView logic here too
                                iconView(iconString: definition.icon)
                                    .font(.title3) // Adjust size if needed
                                    .frame(width: 25, alignment: .center)
                                Text(definition.name)
                                Spacer()
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }

                Section("Custom Habit") {
                    Button("Create & Add Custom Habit") { // Clarify button action
                        showingCustomHabitSheet = true
                    }
                }

                // Add Section for Managing Habits
                Section {
                    // Use NavigationLink to push ManageHabitsView
                    NavigationLink(destination: ManageHabitsView()
                                                .environment(\.managedObjectContext, viewContext)
                                                // Hide the default back button text if desired
                                                .navigationBarBackButtonHidden(false)
                                                .navigationTitle("Manage Habits") // Title for the pushed view
                    ) {
                        Label("Manage All Habits", systemImage: "list.bullet.clipboard")
                    }
                }
            }
            .navigationTitle("Add Habit") // Title for the initial sheet view
            .navigationBarTitleDisplayMode(.inline) // Keep title inline
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: EmptyView() // Remove trailing items to prevent UI conflicts
            )
            .sheet(isPresented: $showingCustomHabitSheet) {
                CreateCustomHabitView(date: self.date) { name, icon in // MODIFIED: Pass self.date explicitly
                    // This closure now calls saveHabit, which handles definition creation
                    saveHabit(name: name, icon: icon)
                }
                .environment(\.managedObjectContext, viewContext)
            }
            .alert("Habit Already Exists", isPresented: $showingDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You have already logged '\(duplicateHabitName)' for this day.")
            }
            // MODIFIED: .onAppear to log date and then seed
            .onAppear {
                seedPredefinedHabitsIfNeeded()
            }
            .interactiveDismissDisabled(false) // Allow sheet to be dismissed by dragging
        }
        // Use .interactiveDismissDisabled() if needed, depending on desired behavior
        // when navigating deeper within the sheet.
    }

    // Helper for displaying icon (copied from HabitCard)
    @ViewBuilder
    private func iconView(iconString: String?) -> some View {
        if let iconStr = iconString,
           iconStr.count == 1,
           iconStr.unicodeScalars.first?.properties.isEmojiPresentation == true
        {
            Text(iconStr)
        } else {
            Image(systemName: iconString ?? "questionmark.circle")
        }
    }


    // Updated function to save habit record with proper session linking for retroactive dates
    private func saveHabit(name: String, icon: String) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let dismissAction = dismiss
        let isToday = calendar.isDateInToday(date)
        
        viewContext.perform {
            do {
                let definitionFetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                definitionFetchRequest.predicate = NSPredicate(format: "name == %@", name)
                definitionFetchRequest.fetchLimit = 1

                let existingDefinitions = try self.viewContext.fetch(definitionFetchRequest)
                var habitDefinition: HabitDefinition
                
                if existingDefinitions.isEmpty {
                    habitDefinition = HabitDefinition(context: self.viewContext)
                    habitDefinition.name = name
                    habitDefinition.icon = icon
                    
                    let manualHabitsFetch: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
                    manualHabitsFetch.predicate = NSPredicate(format: "sortOrder < 100")
                    let sortDescriptor = NSSortDescriptor(keyPath: \HabitDefinition.sortOrder, ascending: false)
                    manualHabitsFetch.sortDescriptors = [sortDescriptor]
                    manualHabitsFetch.fetchLimit = 1
                    
                    if let highestManual = try? self.viewContext.fetch(manualHabitsFetch).first {
                        habitDefinition.sortOrder = min(highestManual.sortOrder + 1, 99)
                    } else {
                        habitDefinition.sortOrder = 50
                    }
                } else {
                    habitDefinition = existingDefinitions[0]
                }

                let recordFetchRequest: NSFetchRequest<HabitRecord> = HabitRecord.fetchRequest()
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                
                recordFetchRequest.predicate = NSPredicate(format: "definition == %@ AND date >= %@ AND date < %@", habitDefinition, startOfDay as CVarArg, endOfDay as CVarArg)
                recordFetchRequest.fetchLimit = 1

                let existingRecords = try self.viewContext.fetch(recordFetchRequest)
                if existingRecords.isEmpty {
                    let newRecord = HabitRecord(context: self.viewContext)
                    newRecord.name = name  // Set the required name field
                    newRecord.date = startOfDay
                    newRecord.value = "true"
                    newRecord.entryDate = Date() // Add entry timestamp
                    newRecord.definition = habitDefinition  // Always set the required relationship
                    
                    // Different logic for today vs retroactive dates
                    if isToday {
                        // For today: Create unresolved habit, will be linked by sync coordinator
                        newRecord.isResolved = false
                        newRecord.sleepSession = nil
                    } else {
                        // For retroactive dates: Find and link the session immediately using displayDate + 1
                        guard let ownershipDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
                            print("Error calculating ownership day for retroactive habit")
                            return
                        }
                        
                        // Look for SleepSessionV2 with ownershipDay = displayDate + 1 (same as DailyHabitsViewModel)
                        let sessionFetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
                        sessionFetchRequest.predicate = NSPredicate(format: "ownershipDay == %@", ownershipDay as NSDate)
                        sessionFetchRequest.fetchLimit = 1
                        
                        let sessions = try self.viewContext.fetch(sessionFetchRequest)
                        if let session = sessions.first {
                            newRecord.isResolved = true
                            newRecord.sleepSession = session
                            print("✅ Linked retroactive habit '\(name)' to session with ownershipDay: \(ownershipDay)")
                        } else {
                            newRecord.isResolved = false
                            newRecord.sleepSession = nil
                            print("⚠️ No session found for retroactive habit '\(name)' with ownershipDay: \(ownershipDay)")
                        }
                    }

                    try self.viewContext.save()
                    
                    DispatchQueue.main.async {
                        dismissAction()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.duplicateHabitName = name
                        self.showingDuplicateAlert = true
                    }
                }
            } catch {
                print("Failed to fetch or save habit: \(error)")
            }
        }
    }

    // Function to seed predefined habits into Core Data if they don't exist
    private func seedPredefinedHabitsIfNeeded() {
        viewContext.perform {
            let predefined: [(name: String, icon: String, order: Int16)] = [
                ("Hot Shower", "shower", 1),
                ("Eyemask", "eye.slash", 2),
                ("Read Book", "book.closed", 3),
                ("No Screens", "tv.slash", 4),
                ("Meditate", "figure.mind.and.body", 5)
            ]

            let allDefinitionNames = predefined.map { $0.name }
            let fetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "name IN %@", allDefinitionNames)

            do {
                let existingDefinitions = try viewContext.fetch(fetchRequest)
                let existingNames = Set(existingDefinitions.map { $0.name })
                var needsSave = false

                for item in predefined {
                    if !existingNames.contains(item.name) {
                        let newDefinition = HabitDefinition(context: viewContext)
                        newDefinition.name = item.name
                        newDefinition.icon = item.icon
                        newDefinition.sortOrder = item.order
                        // Manual habit (no HealthKit ID needed anymore)
                        needsSave = true
                    }
                }

                if needsSave {
                    try viewContext.save()
                }
            } catch {
                print("Failed to check or seed habit definitions: \(error)")
            }
        }
    }
}

// ... existing CreateCustomHabitView (no changes needed here) ...

// Preview might need adjustment to show seeded data
struct HabitSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        // Ensure preview context has seeded data
        let context = PersistenceController.preview.container.viewContext
        // Basic seeding for preview - check if any habits exist
        let fetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
        if (try? context.count(for: fetchRequest)) == 0 {
             let item = HabitDefinition(context: context)
             item.name = "Preview Habit"
             item.icon = "star"
             item.sortOrder = 1
             // Manual habit for preview (no HealthKit ID needed)
             try? context.save()
        }


        return HabitSelectionView(date: Date())
            .environment(\.managedObjectContext, context)
    }
}