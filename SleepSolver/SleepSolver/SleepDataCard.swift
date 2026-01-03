import SwiftUI

struct SleepDataCard: View {
    let label: String
    let value: String
    let iconName: String? // Changed to optional
    var textAlignment: HorizontalAlignment = .leading

    var body: some View {
        HStack(spacing: 10) {
            if let iconName = iconName, !iconName.isEmpty { // Conditionally display icon
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .frame(width: 25)
            }

            VStack(alignment: textAlignment) { // Use the textAlignment property
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            if textAlignment == .leading { // Only add Spacer if alignment is leading
                Spacer() // Push content to the left
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: textAlignment == .center ? .center : .leading) // Adjust frame alignment
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct SleepDataCard_Previews: PreviewProvider {
    static var previews: some View {
        SleepDataCard(label: "Efficiency", value: "85%", iconName: "percent") // Added iconName to preview
            .padding()
        SleepDataCard(label: "Total Sleep", value: "8h 15m", iconName: nil) // Example without icon
            .padding()
    }
}
