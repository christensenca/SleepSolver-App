import SwiftUI

struct DateSliderView: View {
    @Binding var selectedDate: Date
    
    // Define the range of dates to display
    private var dateRange: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Calculate the date 6 months ago
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: today) else {
            // Fallback to 30 days if 6 months calculation fails, though unlikely
            var dates: [Date] = []
            for i in (0...30).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                    dates.append(date)
                }
            }
            return dates
        }

        var dates: [Date] = []
        var currentDate = sixMonthsAgo
        // Iterate from 6 months ago to today, adding each day to the range
        while currentDate <= today {
            dates.append(currentDate)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break // Should not happen
            }
            currentDate = nextDay
        }
        return dates
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) { // Add spacing between dates
                    ForEach(dateRange, id: \.self) { date in
                        DateItemView(date: date, isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate))
                            .onTapGesture {
                                selectedDate = date
                            }
                            .id(date) // Assign ID for ScrollViewReader
                    }
                }
                .padding(.horizontal) // Add horizontal padding to the HStack
            }
            .frame(height: 60) // Give the slider a fixed height
            .onChange(of: selectedDate) { _, newDate in
                // Scroll to the selected date when it changes (e.g., via swipe)
                withAnimation {
                    proxy.scrollTo(newDate, anchor: .center)
                }
            }
            .onAppear {
                 // Scroll to the initial selected date
                 proxy.scrollTo(selectedDate, anchor: .center)
            }
        }
    }
}

// View for a single date item in the slider
struct DateItemView: View {
    let date: Date
    let isSelected: Bool
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // Short day name (e.g., "Mon")
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d" // Day number (e.g., "5")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Display "Today" or the short day name
            Text(Calendar.current.isDateInToday(date) ? "Today" : dayFormatter.string(from: date))
                .font(.caption)
                .foregroundColor(isSelected ? .white : .gray)
            
            // Display the day number
            Text(dateFormatter.string(from: date))
                .font(.headline)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(8) // Add padding around the number
                .background(isSelected ? Color.accentColor : Color.clear) // Blue background if selected
                .clipShape(Circle()) // Make the background circular
        }
        .frame(width: 50) // Give each item a fixed width
    }
}

// Preview Provider
struct DateSliderView_Previews: PreviewProvider {
    @State static var previewSelectedDate = Calendar.current.startOfDay(for: Date())

    static var previews: some View {
        VStack {
            DateSliderView(selectedDate: $previewSelectedDate)
                .background(Color.gray.opacity(0.2)) // Add background for visibility
            Text("Selected: \(previewSelectedDate, style: .date)")
        }
        .padding()
    }
}
