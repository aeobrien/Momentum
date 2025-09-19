import SwiftUI
import CoreData

enum TodoViewFilter {
    case eligible
    case ineligible
    case all
    
    var description: String {
        switch self {
        case .eligible:
            return "Due Tasks"
        case .ineligible:
            return "Not Due"
        case .all:
            return "All Tasks"
        }
    }
}

struct ToDoView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var cdTasks: FetchedResults<CDTask>

    @State private var selectedFilter: TodoViewFilter = .eligible
    @State private var completedTaskId: UUID? = nil
    @State private var isAnimating = false
    @State private var infoMode = false

    private let logger = AppLogger.create(subsystem: "com.app.ToDoView", category: "UI")

    // Helper functions for formatting time
    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if days >= 365 {
            let years = days / 365
            return "\(years) year\(years == 1 ? "" : "s") ago"
        } else if days >= 30 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else if days >= 7 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if days >= 1 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if hours >= 1 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            return "less than 1 hour ago"
        }
    }

    private func formatRepetitionInterval(_ seconds: Int32) -> String {
        if seconds == 0 {
            return "Daily"
        }

        let hours = seconds / 3600
        let days = seconds / 86400

        if days >= 365 {
            let years = days / 365
            return "Every \(years) year\(years == 1 ? "" : "s")"
        } else if days >= 30 {
            let months = days / 30
            return "Every \(months) month\(months == 1 ? "" : "s")"
        } else if days >= 7 {
            let weeks = days / 7
            return "Every \(weeks) week\(weeks == 1 ? "" : "s")"
        } else if days >= 1 {
            return "Every \(days) day\(days == 1 ? "" : "s")"
        } else if hours >= 1 {
            return "Every \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let minutes = seconds / 60
            return "Every \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }

    private func nextDueText(_ task: CDTask) -> String? {
        guard let lastCompleted = task.lastCompleted,
              task.repetitionInterval >= 0 else {
            return nil
        }

        let nextDueDate = lastCompleted.addingTimeInterval(TimeInterval(task.repetitionInterval))
        let now = Date()
        let interval = nextDueDate.timeIntervalSince(now)

        if interval <= 0 {
            return "due now"
        }

        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if days >= 365 {
            let years = days / 365
            return "in \(years) year\(years == 1 ? "" : "s")"
        } else if days >= 30 {
            let months = days / 30
            return "in \(months) month\(months == 1 ? "" : "s")"
        } else if days >= 7 {
            let weeks = days / 7
            return "in \(weeks) week\(weeks == 1 ? "" : "s")"
        } else if days >= 1 {
            return "in \(days) day\(days == 1 ? "" : "s")"
        } else if hours >= 1 {
            return "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "in less than 1 hour"
        }
    }
    
    init() {
        let request: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        _cdTasks = FetchRequest(fetchRequest: request)
    }
    
    /// Determines if a task is due for completion, considering daily reset and repetition intervals.
    private func isDueForCompletion(_ task: CDTask) -> Bool {
        logger.debug("Checking due status for task: \(task.taskName ?? "Unnamed")")

        // Rule 1: Always due if never completed.
        guard let lastCompleted = task.lastCompleted else {
            logger.debug("- Due: Never completed.")
            return true
        }

        // Rule 2: Daily Reset (repetitionInterval == 0)
        if task.repetitionInterval == 0 {
            let isToday = Calendar.current.isDateInToday(lastCompleted)
            logger.debug("- Daily Reset Task: Last completed \(isToday ? "today" : "before today"). Due: \(!isToday)")
            // Due only if it wasn't completed today.
            return !isToday
        }

        // Rule 3: Interval-based eligibility (repetitionInterval > 0)
        let now = Date()
        let calendar = Calendar.current

        // Calculate when the task will be due based on the interval
        let dueDate = lastCompleted.addingTimeInterval(TimeInterval(task.repetitionInterval))

        // Get the start of the day when the task will be due
        let dueDateStartOfDay = calendar.startOfDay(for: dueDate)

        // If we're past the start of the due day, the task is due
        // This allows tasks to be completed from midnight on their due date
        let isDue = now >= dueDateStartOfDay

        let secondsSinceCompletion = now.timeIntervalSince(lastCompleted)
        let requiredInterval = TimeInterval(task.repetitionInterval)
        logger.debug("- Interval Task: \(String(format: "%.1f", secondsSinceCompletion))s since completion. Required: \(String(format: "%.1f", requiredInterval))s. Due from midnight: \(isDue)")
        return isDue
    }
    
    private func filteredTasks() -> [CDTask] {
        logger.debug("Filtering tasks with criteria: \(selectedFilter.description)")
        let tasksMatchingDueDateCriteria: [CDTask]
        
        switch selectedFilter {
        case .eligible:
            tasksMatchingDueDateCriteria = Array(cdTasks.filter { isDueForCompletion($0) })
        case .ineligible:
            tasksMatchingDueDateCriteria = Array(cdTasks.filter { !isDueForCompletion($0) })
        case .all:
            tasksMatchingDueDateCriteria = Array(cdTasks)
        }
        
        // Now, filter out session tasks from the above results
        let nonSessionTasks = tasksMatchingDueDateCriteria.filter { !$0.isSessionTask } // Filter using the actual property
        
        logger.debug("Filtered \(tasksMatchingDueDateCriteria.count - nonSessionTasks.count) session tasks. Returning \(nonSessionTasks.count) non-session tasks.")
        return nonSessionTasks
    }
    
    private func markTaskComplete(_ task: CDTask) {
        withAnimation {
            completedTaskId = task.uuid
            isAnimating = true
        }
        
        // Delay the actual completion to allow animation to play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            task.lastCompleted = Date()
            
            do {
                try viewContext.save()
                logger.info("Successfully marked task as complete: \(task.taskName ?? "")")
            } catch {
                logger.error("Failed to mark task as complete", error: error)
            }
            
            // Reset animation state after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    completedTaskId = nil
                    isAnimating = false
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            // Filter Selection
            Picker("Filter", selection: $selectedFilter) {
                ForEach([TodoViewFilter.eligible, .ineligible, .all], id: \.self) { filter in
                    Text(filter.description).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 8)
            
            List {
                ForEach(filteredTasks()) { task in
                    HStack {
                        // Checkbox
                        Button(action: {
                            markTaskComplete(task)
                        }) {
                            Image(systemName: completedTaskId == task.uuid ? "checkmark.square.fill" : "square")
                                .foregroundColor(.blue)
                                .imageScale(.large)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        // Task details
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.taskName ?? "")
                                .font(.headline)

                            // Show repetition interval, last completed, and next due on one line
                            HStack(spacing: 6) {
                                // Repetition interval (or Daily)
                                if task.repetitionInterval >= 0 {
                                    Text(formatRepetitionInterval(task.repetitionInterval))
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }

                                // Last completed
                                if let lastCompleted = task.lastCompleted {
                                    Text("• Last: \(formatRelativeTime(lastCompleted))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("• Never completed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Next due
                                if let nextDue = nextDueText(task) {
                                    Text("• Next: \(nextDue)")
                                        .font(.caption)
                                        .foregroundColor(nextDue == "due now" ? .orange : .secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Eligibility indicator
                        if isDueForCompletion(task) {
                            Text("Due")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                        }
                        
                        // Essentiality indicator
                        Circle()
                            .fill(essentialityColor(task.essentiality))
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 4)
                    .opacity(completedTaskId == task.uuid ? 0.5 : 1.0)
                    .offset(x: completedTaskId == task.uuid ? 50 : 0)
                    .animation(.easeInOut(duration: 0.3), value: completedTaskId)
                }
            }
            .listStyle(PlainListStyle())
        }
        }
        .infoOverlay(
            showInfo: $infoMode,
            title: "To-Do",
            description: "Track tasks due for completion. Tap checkboxes to mark tasks complete. Use tabs to filter by due status. Priority is shown by colored dots."
        )
        .navigationTitle("To Do")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: InfoButton(showInfo: $infoMode)
        )
    }
    
    private func essentialityColor(_ value: Int16) -> Color {
        switch value {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .gray
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ToDoView_Previews: PreviewProvider {
    static var previews: some View {
        ToDoView()
            .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
    }
}
