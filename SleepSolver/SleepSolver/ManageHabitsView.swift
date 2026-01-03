import SwiftUI
import CoreData

struct ManageHabitsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // Fetch all habit definitions, sorted (all are now user-manageable)
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \HabitDefinition.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \HabitDefinition.name, ascending: true)
        ]
    ) private var habitDefinitions: FetchedResults<HabitDefinition>

    // State for presenting the edit sheet
    @State private var showingEditSheet = false
    @State private var habitToEdit: HabitDefinition?

    var body: some View {
        NavigationView {
            List {
                ForEach(habitDefinitions) { definition in
                    HStack {
                        iconView(iconString: definition.icon)
                            .font(.title3)
                            .frame(width: 25, alignment: .center)
                        Text(definition.name)
                        Spacer()
                        if definition.isArchived {
                            Text("Archived")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .contentShape(Rectangle()) // Make entire row tappable
                    .onTapGesture {
                        // All habits are now user-editable
                        habitToEdit = definition
                        showingEditSheet = true
                    }
                    // Add swipe actions for archiving/unarchiving ALL habits
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            toggleArchiveStatus(for: definition)
                        } label: {
                            Label(definition.isArchived ? "Unarchive" : "Archive",
                                  systemImage: definition.isArchived ? "arrow.uturn.backward.circle.fill" : "archivebox.fill")
                        }
                        .tint(definition.isArchived ? .blue : .gray)
                    }
                }
            }
            .navigationTitle("Manage Habits")
            .navigationBarItems(trailing: Button("Done") {
                dismiss() // Assuming this view is presented modally
            })
            .sheet(item: $habitToEdit) { habit in
                 // Present EditHabitView (created in previous step)
                 EditHabitView(habitDefinition: habit)
                     .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    // Helper for displaying icon
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

    // Function to toggle the archive status
    private func toggleArchiveStatus(for definition: HabitDefinition) {
        viewContext.perform {
            definition.isArchived.toggle()
            do {
                try viewContext.save()
                print("Toggled archive status for '\(definition.name)' to \(definition.isArchived)")
            } catch {
                print("Failed to toggle archive status: \(error)")
                // Optionally revert the change in memory
                viewContext.rollback()
            }
        }
    }
}

struct ManageHabitsView_Previews: PreviewProvider {
    static var previews: some View {
        // Add sample data for preview
        let context = PersistenceController.preview.container.viewContext
        let def1 = HabitDefinition(context: context)
        def1.name = "Test Predefined"
        def1.icon = "star"
        // Manual habit test data (no HealthKit ID needed)
        def1.sortOrder = 1
        def1.isArchived = false

        let def2 = HabitDefinition(context: context)
        def2.name = "Test Custom"
        def2.icon = "👍"
        // Manual habit test data
        def2.sortOrder = 101
        def2.isArchived = false

        let def3 = HabitDefinition(context: context)
        def3.name = "Test Archived Custom"
        def3.icon = "🚀"
        // Manual habit test data
        def3.sortOrder = 102
        def3.isArchived = true

        return ManageHabitsView()
            .environment(\.managedObjectContext, context)
    }
}