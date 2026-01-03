// filepath: /Users/cadechristensen/Source/SleepSolver/SleepSolver/CreateCustomHabitView.swift
import SwiftUI
import CoreData

struct CreateCustomHabitView: View {
    let date: Date
    // Closure to call when saving is successful
    let onSave: (String, String) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var habitName: String = ""
    @State private var habitIcon: String = "" // Will hold the emoji

    // Basic validation state
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("Habit Name (e.g., Journal)", text: $habitName)

                TextField("Icon (Tap 🌐 or 😀 to select emoji)", text: $habitIcon)
                    // Limit input to a single character (basic emoji check)
                    .onChange(of: habitIcon) {
                         if habitIcon.count > 1 {
                            habitIcon = String(habitIcon.prefix(1))
                         }
                    }
            }
            .navigationTitle("Create Custom Habit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    validateAndSave()
                }
            )
            .alert("Invalid Input", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationErrorMessage)
            }
        }
    }

    private func validateAndSave() {
        // Trim whitespace
        let trimmedName = habitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIcon = habitIcon.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validation
        guard !trimmedName.isEmpty else {
            validationErrorMessage = "Please enter a name for the habit."
            showingValidationError = true
            return
        }
        guard !trimmedIcon.isEmpty else {
            validationErrorMessage = "Please enter an emoji icon for the habit."
            showingValidationError = true
            return
        }
        // Rudimentary check if it's likely an emoji (single character)
        guard trimmedIcon.count == 1 && trimmedIcon.unicodeScalars.first?.properties.isEmojiPresentation == true else {
             validationErrorMessage = "Please enter a single valid emoji for the icon."
             showingValidationError = true
             return
        }


        // If validation passes, call the onSave closure from HabitSelectionView
        onSave(trimmedName, trimmedIcon)
        // Let the caller (HabitSelectionView) handle dismissal via its own logic.
    }
}

// Preview needs adjustment if needed, basic setup:
struct CreateCustomHabitView_Previews: PreviewProvider {
    static var previews: some View {
        CreateCustomHabitView(date: Date()) { _, _ in
            // Dummy closure for preview
            print("Preview Save Tapped")
        }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
