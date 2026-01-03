import SwiftUI
import CoreData

struct SleepMetricsCardView: View {
    let displayDate: Date
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingRecoveryDetail = false
    @State private var showingSleepScoreDetail = false
    
    // Use @FetchRequest to directly observe Core Data changes for this specific date
    @FetchRequest private var sessions: FetchedResults<SleepSessionV2>
    
    init(displayDate: Date) {
        self.displayDate = displayDate
        
        // Calculate the 6pm-to-6pm window for the display date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: displayDate)
        let endOfWindow = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startOfDay) ?? startOfDay
        let startOfWindow = calendar.date(byAdding: .hour, value: -24, to: endOfWindow) ?? endOfWindow
        
        // Set up the fetch request to observe sessions for this specific date window
        let fetchRequest: NSFetchRequest<SleepSessionV2> = SleepSessionV2.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "ownershipDay >= %@ AND ownershipDay < %@", 
                                           startOfWindow as CVarArg, 
                                           endOfWindow as CVarArg)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "startDateUTC", ascending: false)]
        fetchRequest.fetchLimit = 1
        
        self._sessions = FetchRequest(fetchRequest: fetchRequest)
    }
    
    // Get the current session from the fetch request
    private var currentSession: SleepSessionV2? {
        return sessions.first
    }
    
    var body: some View {
        ChartCardView {
            VStack(spacing: 30) {
                // Main scores section
                HStack {
                    Spacer()
                    // Sleep Score
                    Button(action: {
                        showingSleepScoreDetail = true
                    }) {
                        UnifiedScoreArcView(
                            sessionV2: currentSession,
                            scoreType: .sleep,
                            title: "Sleep Score",
                            color: .blue,
                            size: 140, // Increased size for better presence
                            animationKey: "sleepScore-\(currentSession?.objectID.uriRepresentation().absoluteString ?? "nil")-\(Date().timeIntervalSince1970)"
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
                
                // Always show Recovery Metrics View
                if let session = currentSession, session.isFinalized {
                    // Session is finalized - make it clickable for detail view
                    Button(action: {
                        showingRecoveryDetail = true
                    }) {
                        RecoveryMetricsView(session: session)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // No session, session not finalized, or no data yet - show with unknown status
                    RecoveryMetricsView(session: currentSession)
                }

            }
        }
        .sheet(isPresented: $showingRecoveryDetail) {
            if let session = currentSession {
                RecoveryDetailView(sessionV2: session)
            } else {
                RecoveryDetailView(sessionV2: nil)
            }
        }
        .sheet(isPresented: $showingSleepScoreDetail) {
            if let session = currentSession {
                SleepScoreDetailView(sessionV2: session)
            } else {
                SleepScoreDetailView()
            }
        }
    }
}

// MARK: - Supporting Views

struct MetricItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ScoreButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let sessionV2 = SleepSessionV2(context: context)
    
    // Set sample data
    sessionV2.sleepScore = 85
    sessionV2.totalTimeInBed = 8.5 * 3600 // 8.5 hours in seconds
    sessionV2.totalSleepTime = 7.8 * 3600 // 7.8 hours in seconds
    sessionV2.hrvStatus = 0.8      // Optimal z-score
    sessionV2.rhrStatus = -0.3     // Good z-score (adjusted for lower is better)
    sessionV2.temperatureStatus = 1.7  // Attention z-score (adjusted for lower is better)
    sessionV2.respStatus = 0.4     // Good z-score (flexible interpretation)
    sessionV2.spo2Status = -0.6    // Good z-score (flexible interpretation)
    sessionV2.isFinalized = true // Set as finalized for preview
    sessionV2.ownershipDay = Calendar.current.startOfDay(for: Date())
    
    return SleepMetricsCardView(displayDate: Calendar.current.startOfDay(for: Date()))
        .environment(\.managedObjectContext, context)
        .padding()
        .background(Color(.systemGroupedBackground))
}
