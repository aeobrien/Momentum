import SwiftUI
import CoreData

/// Represents an error message that conforms to Identifiable
struct IdentifiableError: Identifiable {
    var id: String { message }
    let message: String
}

struct TaskDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var cdTask: CDTask
    @State private var showEdit = false
    @State private var errorMessage: IdentifiableError?
    
    private let logger = AppLogger.create(subsystem: "com.app.TaskDetailView", category: "UI")
    
    private func formatRepetitionInterval(_ seconds: Int32) -> String {
        let days = seconds / 86400
        return "\(days) day\(days == 1 ? "" : "s")"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func calculateEligibilityStatus() -> (isEligible: Bool, daysRemaining: Int?) {
        guard let lastCompleted = cdTask.lastCompleted,
              cdTask.repetitionInterval > 0 else {
            return (true, nil)
        }
        
        let nextEligibleDate = lastCompleted.addingTimeInterval(TimeInterval(cdTask.repetitionInterval))
        let now = Date()
        
        if nextEligibleDate > now {
            let days = Calendar.current.dateComponents([.day], from: now, to: nextEligibleDate).day ?? 0
            return (false, days)
        } else {
            return (true, nil)
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%dh %dm", hours, remainingMinutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    var body: some View {
        List {
            Section(header: Text("DETAILS")) {
                HStack {
                    Text("Task Name")
                    Spacer()
                    Text(cdTask.taskName ?? "")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Essentiality")
                    Spacer()
                    Text(cdTask.essentiality == 3 ? "Essential" :
                         cdTask.essentiality == 2 ? "Core" : "Non-Essential")
                        .foregroundColor(cdTask.essentiality == 3 ? .red :
                                       cdTask.essentiality == 2 ? .orange : .green)
                }
                
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(cdTask.minDuration == cdTask.maxDuration ?
                         "\(cdTask.minDuration) minutes" :
                         "\(cdTask.minDuration)-\(cdTask.maxDuration) minutes")
                        .foregroundColor(.secondary)
                }
                
                if cdTask.repetitionInterval > 0 {
                    HStack {
                        Text("Repeat Every")
                        Spacer()
                        Text(formatRepetitionInterval(cdTask.repetitionInterval))
                            .foregroundColor(.secondary)
                    }
                } else if cdTask.repetitionInterval == 0 {
                    HStack {
                        Text("Repeat Every")
                        Spacer()
                        Text("Daily")
                            .foregroundColor(.secondary)
                    }
                }

                // Re-enabled Session Task display
                HStack {
                    Text("Session Task Only")
                    Spacer()
                    // Revert to direct property access, assuming migration works
                    Text(cdTask.isSessionTask ? "Yes" : "No") 
                        .foregroundColor(.secondary)
                }
                
                // Average Time Tracking display
                HStack {
                    Text("Track Average Time")
                    Spacer()
                    Text(cdTask.shouldTrackAverageTime ? "Yes" : "No")
                        .foregroundColor(.secondary)
                }
                
                // Show average completion time if available
                if cdTask.shouldTrackAverageTime {
                    if let avgTime = cdTask.averageCompletionTime {
                        HStack {
                            Text("Average Completion Time")
                            Spacer()
                            Text(formatTimeInterval(avgTime))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if let lastCompleted = cdTask.lastCompleted {
                Section(header: Text("HISTORY AND ELIGIBILITY")) {
                    HStack {
                        Text("Last Completed")
                        Spacer()
                        Text(formatDate(lastCompleted))
                            .foregroundColor(.secondary)
                    }
                    
                    if cdTask.repetitionInterval > 0 {
                        let eligibilityStatus = calculateEligibilityStatus()
                        HStack {
                            Text("Status")
                            Spacer()
                            if eligibilityStatus.isEligible {
                                Text("Eligible now")
                                    .foregroundColor(.green)
                            } else if let daysRemaining = eligibilityStatus.daysRemaining {
                                Text("Eligible in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        let daysSinceCompletion = Calendar.current.dateComponents([.day], from: lastCompleted, to: Date()).day ?? 0
                        HStack {
                            Text("Days Since Completion")
                            Spacer()
                            Text("\(daysSinceCompletion) day\(daysSinceCompletion == 1 ? "" : "s")")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Section(header: Text("HISTORY AND ELIGIBILITY")) {
                    HStack {
                        Text("Last Completed")
                        Spacer()
                        Text("Never completed")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        Text("Eligible now")
                            .foregroundColor(.green)
                    }
                }
            }
            
            Section(header: Text("ACTIONS")) {
                Button(action: {
                    showEdit = true
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit Task")
                    }
                }
                .foregroundColor(.blue)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Task Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            AddTaskView(task: cdTask.toDomainModel()) { updatedTask in
                updateTask(updatedTask)
            }
        }
        .alert(item: $errorMessage) { error in
            Alert(title: Text("Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
    
    private func updateTask(_ updatedTask: CustomTask) {
        cdTask.updateCDTask(from: updatedTask)
        
        do {
            try viewContext.save()
            logger.info("Successfully updated task: \(updatedTask.taskName)")
            showEdit = false
        } catch {
            logger.error("Failed to update task", error: error)
            errorMessage = IdentifiableError(message: error.localizedDescription)
        }
    }
}

struct TaskDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = CoreDataStack.shared.viewContext
        let cdTask = CDTask(context: context)
        cdTask.taskName = "Sample Task"
        cdTask.essentiality = 2
        cdTask.minDuration = 10
        cdTask.maxDuration = 20
        cdTask.lastCompleted = Date().addingTimeInterval(-86400 * 2) // 2 days ago
        cdTask.repetitionInterval = 86400 * 5 // 5 days
        
        return NavigationView {
            TaskDetailView(cdTask: cdTask)
                .environment(\.managedObjectContext, context)
        }
    }
}
