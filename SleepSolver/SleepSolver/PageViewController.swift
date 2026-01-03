import SwiftUI
import UIKit

// Define protocol near the top of the file or in its own file
protocol DateProviderView: View {
    var date: Date { get }
}

// Make PageViewController generic over the Content view it displays
struct PageViewController<Content: View>: UIViewControllerRepresentable {
    @Binding var selectedDate: Date
    // Closure to create the content view for a given date
    var content: (Date) -> Content

    @Environment(\.managedObjectContext) private var viewContext // Keep context needed by Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal)
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator

        // Set the initial view controller using the content closure
        let initialVC = context.coordinator.hostingController(for: selectedDate)
        pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)

        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self

        // Get the date currently displayed by the UIPageViewController
        guard let currentVC = pageViewController.viewControllers?.first,
              let currentlyDisplayedDate = context.coordinator.date(from: currentVC) else {
            // If we can't get the current date, maybe reset to selectedDate? Or log error.
            // For now, let's try setting it directly if we can't determine the current one.
            let targetVC = context.coordinator.hostingController(for: selectedDate)
            pageViewController.setViewControllers([targetVC], direction: .forward, animated: false)
            return
        }

        // Compare with the selectedDate binding
        let calendar = Calendar.current
        if !calendar.isDate(currentlyDisplayedDate, inSameDayAs: selectedDate) {
            // Dates don't match, so update the UIPageViewController programmatically
            let direction: UIPageViewController.NavigationDirection = selectedDate > currentlyDisplayedDate ? .forward : .reverse
            let targetVC = context.coordinator.hostingController(for: selectedDate)
            
            // Use a weak reference to self to avoid retain cycles in the completion block if needed
            // For setViewControllers, it might not be strictly necessary unless doing complex async work after
            pageViewController.setViewControllers([targetVC], direction: direction, animated: true) { finished in
                // Optional: Add completion logic if needed, e.g., re-enable gestures if disabled during animation
            }
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageViewController
        let calendar = Calendar.current

        init(_ pageViewController: PageViewController) {
            self.parent = pageViewController
        }

        // Helper to create the specific content view hosted in UIHostingController
        func hostingController(for date: Date) -> UIViewController {
            // Use the parent's content closure to create the view
            let view = parent.content(date)
                // Explicitly add environment values needed by the content view
                .environment(\.managedObjectContext, parent.viewContext)

            let hostingController = UIHostingController(rootView: view)
            // Store the date in the hosting controller for retrieval in delegate/datasource (keep as fallback)
            hostingController.view.tag = Int(date.timeIntervalSinceReferenceDate)
            return hostingController
        }

        // Helper to get the date back from a view controller
        func date(from viewController: UIViewController) -> Date? {
            // Try getting date directly from the rootView if it conforms to DateProviderView
            if let hostingVC = viewController as? UIHostingController<Content>,
               let dateProviderView = hostingVC.rootView as? any DateProviderView {
                 return dateProviderView.date
            }
            // Fallback to tag if rootView doesn't conform or isn't accessible
            guard viewController.view.tag != 0 else { return nil }
            return Date(timeIntervalSinceReferenceDate: TimeInterval(viewController.view.tag))
        }

        // MARK: - UIPageViewControllerDataSource
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let currentDate = date(from: viewController),
                  let previousDate = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                return nil
            }
            // Optional: Trigger data pre-fetching if needed
            // parent.viewModel.fetchWeekBatch(around: previousDate) // Example
            return self.hostingController(for: previousDate)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let currentDate = date(from: viewController) else {
                return nil
            }

            // Check if the current date is today or later
            if calendar.isDateInToday(currentDate) || currentDate > Date() {
                return nil // Don't allow swiping forward from today or future dates
            }

            // Calculate the next date
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                return nil
            }

            // Optional: Trigger data pre-fetching if needed
            // parent.viewModel.fetchWeekBatch(around: nextDate) // Example
            return self.hostingController(for: nextDate)
        }

        // MARK: - UIPageViewControllerDelegate
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed,
               let currentVC = pageViewController.viewControllers?.first,
               let newDate = date(from: currentVC) { // Use the updated helper
                // Update the binding in the parent SwiftUI view
                parent.selectedDate = newDate
            }
        }
    }
}

// Optional: Protocol to help retrieve date if needed in updateUIViewController
/*
 protocol DateableView: View {
    var date: Date? { get }
 }
 */
