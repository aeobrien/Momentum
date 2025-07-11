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
        let secondsSinceCompletion = now.timeIntervalSince(lastCompleted)
        let requiredInterval = TimeInterval(task.repetitionInterval) // Assuming repetitionInterval is stored in seconds
        
        let isDue = secondsSinceCompletion >= requiredInterval
        logger.debug("- Interval Task: \(String(format: "%.1f", secondsSinceCompletion))s since completion. Required: \(String(format: "%.1f", requiredInterval))s. Due: \(isDue)")
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
                        VStack(alignment: .leading) {
                            Text(task.taskName ?? "")
                                .font(.headline)
                            
                            if let lastCompleted = task.lastCompleted {
                                Text("Last completed: \(lastCompleted, formatter: dateFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Never completed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if task.repetitionInterval > 0 {
                                Text("Repeats every \(task.repetitionInterval / 86400) days")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
        .grayscale(infoMode ? 1 : 0)
        .disabled(infoMode)
        
        // Info overlay
        if infoMode {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    infoMode = false
                }
            
            VStack(spacing: 20) {
                Text("To-Do View")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("This page shows all non session tasks which are currently due for completion, along with their repetition interval and their last completion date. Tap a task's checkbox to mark it as completed. Use the tabs menu to view tasks that aren't due for completion, or all tasks. The task's priority rating is indicated by the coloured dot on the right side of its entry.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Got it") {
                    infoMode = false
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
        }
        .navigationTitle("To Do")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: Button(action: {
                infoMode.toggle()
            }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
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
