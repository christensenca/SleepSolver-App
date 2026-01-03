import SwiftUI

struct HeartRateHRVChartView: View {
    var body: some View {
        VStack(spacing: 15) {
            // Heart Rate Chart - Independent controls
            HeartRateChartView()
            
            // HRV Chart - Independent controls  
            HRVChartView()
        }
    }
}

// MARK: - Preview Helper
private extension HeartRateHRVChartView {
    static func makePreviewViewModel() -> NightlySleepViewModel {
        let context = PersistenceController.preview.container.viewContext
        let hkManager = HealthKitManager.shared
        let viewModel = NightlySleepViewModel(context: context, healthKitManager: hkManager)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let heartRates = [58.0, 62.0, 55.0, 60.0, 64.0, 59.0, 57.0]
        let hrvValues = [42.3, 38.7, 45.1, 40.2, 35.8, 43.6, 41.9]
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -(6-i), to: today) {
                let session = SleepSessionV2(context: context)
                session.ownershipDay = date
                session.averageHeartRate = heartRates[i]
                session.averageHRV = hrvValues[i]
                let key = viewModel.cacheKey(for: date)
                viewModel.sleepSessions[key] = session
            }
        }
        return viewModel
    }
}

#Preview {
    HeartRateHRVChartView()
        .environmentObject(HeartRateHRVChartView.makePreviewViewModel())
        .padding()
}
