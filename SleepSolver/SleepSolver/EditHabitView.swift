import SwiftUI
import CoreData

struct EditHabitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // The habit definition being edited
    @ObservedObject var habitDefinition: HabitDefinition

    // Local state bound to the text fields
    @State private var editableName: String
    @State private var editableIcon: String // Emoji

    // Validation state
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""

    // Initializer to populate state from the passed object
    init(habitDefinition: HabitDefinition) {
        self.habitDefinition = habitDefinition
        _editableName = State(initialValue: habitDefinition.name)
        _editableIcon = State(initialValue: habitDefinition.icon)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("Habit Name", text: $editableName)

                TextField("Icon (Emoji)", text: $editableIcon)
                    .onChange(of: editableIcon) {
                         if editableIcon.count > 1 {
                            editableIcon = String(editableIcon.prefix(1))
                         }
                    }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    validateAndSaveChanges()
                }
            )
            .alert("Invalid Input", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationErrorMessage)
            }
        }
    }

    private func validateAndSaveChanges() {
        let trimmedName = editableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIcon = editableIcon.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validation (similar to CreateCustomHabitView)
        guard !trimmedName.isEmpty else {
            validationErrorMessage = "Habit name cannot be empty."
            showingValidationError = true
            return
        }
        guard !trimmedIcon.isEmpty else {
            validationErrorMessage = "Habit icon cannot be empty."
            showingValidationError = true
            return
        }
        guard trimmedIcon.count == 1 && trimmedIcon.unicodeScalars.first?.properties.isEmojiPresentation == true else {
             validationErrorMessage = "Please enter a single valid emoji for the icon."
             showingValidationError = true
             return
        }

        // Check if name changed and if it conflicts with another existing definition
        if trimmedName != habitDefinition.name {
            let fetchRequest: NSFetchRequest<HabitDefinition> = HabitDefinition.fetchRequest()
            // Find if another definition (excluding the current one) has the new name
            fetchRequest.predicate = NSPredicate(format: "name == %@ AND self != %@", trimmedName, habitDefinition)
            fetchRequest.fetchLimit = 1

            do {
                let count = try viewContext.count(for: fetchRequest)
                if count > 0 {
                    validationErrorMessage = "Another habit with the name '\(trimmedName)' already exists."
                    showingValidationError = true
                    return
                }
            } catch {
                 print("Error checking for duplicate habit name during edit: \(error)")
                 // Proceed cautiously or show a generic error
            }
        }


        // If validation passes, update the Core Data object
        viewContext.perform {
            habitDefinition.name = trimmedName
            habitDefinition.icon = trimmedIcon
            // Note: We also need to update associated HabitRecords if name/icon changed!
            // This can be complex. For now, we only update the definition.
            // A better approach might involve relationships or fetching/updating records.

            do {
                try viewContext.save()
                print("Habit definition '\(trimmedName)' updated.")
                dismiss()
            } catch {
                print("Failed to save habit definition changes: \(error)")
                viewContext.rollback() // Rollback changes on error
            }
        }
    }
}

// Preview for EditHabitView
struct EditHabitView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let sampleHabit = HabitDefinition(context: context)
        sampleHabit.name = "Sample Custom Habit"
        sampleHabit.icon = "💡"
        // Manual habit for preview (no HealthKit ID needed)
        sampleHabit.isArchived = false
        sampleHabit.sortOrder = 100

        return EditHabitView(habitDefinition: sampleHabit)
            .environment(\.managedObjectContext, context)
    }
}