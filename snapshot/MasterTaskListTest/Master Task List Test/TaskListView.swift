import SwiftUI

enum SortOption: String, CaseIterable {
    case alphabeticalAZ
    case lastCompletedAscending
    case lastCompletedDescending
    case repetitionIntervalAscending
    case repetitionIntervalDescending
    case timeUntilDue
    case durationAscending
    case durationDescending

    var displayName: String {
        switch self {
        case .alphabeticalAZ:
            return "A-Z"
        case .lastCompletedAscending:
            return "Last Completed (Asc)"
        case .lastCompletedDescending:
            return "Last Completed (Desc)"
        case .repetitionIntervalAscending:
            return "Repetition Interval (Asc)"
        case .repetitionIntervalDescending:
            return "Repetition Interval (Desc)"
        case .timeUntilDue:
            return "Time Until Due"
        case .durationAscending:
            return "Duration (Asc)"
        case .durationDescending:
            return "Duration (Desc)"
        }
    }
}

struct TaskListView: View {
    @ObservedObject var taskManager: CustomTaskManager
    @State private var tasks: [CustomTask] = []
    @State private var expandedTasks: Set<String> = []
    @State private var selectedSortOption: SortOption = .timeUntilDue
    @State private var isEditPresented: Bool = false
    @State private var selectedTask: CustomTask?
    @State private var isAddPresented: Bool = false
    @State private var newTask = CustomTask(UUID: "", taskName: "", essentiality: 1, minDuration: 60, maxDuration: 60, lastCompleted: "", repetitionInterval: 0, order: nil)
    @State private var deletionMessage: String? // Changed to @State
    
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    newTask = CustomTask(UUID: "", taskName: "", essentiality: 1, minDuration: 60, maxDuration: 60, lastCompleted: "", repetitionInterval: 0, order: nil)
                    isAddPresented = true
                }) {
                    Text("Add Task")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: resetAllLastCompletedDates) {
                    Text("Reset Last Completed Dates")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.bottom, 10)
            
            HStack {
                Text("Sort tasks by:")
                    .font(.headline)
                Picker("Sort by:", selection: $selectedSortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, 10)
            }
            .padding(.bottom, 10)
            
            List(sortedTasks) { task in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedTasks.contains(task.UUID) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedTasks.removeAll()
                                expandedTasks.insert(task.UUID)
                            } else {
                                expandedTasks.remove(task.UUID)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Essentiality: \(formattedEssentiality(task.essentiality))")
                            .font(.subheadline)
                        
                        Text("Duration: \(formattedDuration(min: task.minDuration, max: task.maxDuration))")
                            .font(.subheadline)
                        
                        Text("Repetition: \(formattedRepetitionInterval(task.repetitionInterval))")
                            .font(.subheadline)
                        
                        Text("Last Completed: \(formattedLastCompleted(task.lastCompleted))")
                            .font(.subheadline)
                        
                        HStack {
                            Button("Edit") {
                                selectedTask = task
                                isEditPresented = true
                            }
                            .padding(.trailing, 10)
                            
                            Button("Delete") {
                                deleteTask(task)
                            }
                            .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 5)
                } label: {
                    VStack(alignment: .leading) {
                        Text(task.taskName)
                            .font(.headline)
                        
                        Text("Time Until Due: \(formattedTimeUntilDue(task))")
                            .font(.subheadline)
                            .foregroundColor(isTaskAvailable(task) ? .primary : .gray)
                    }
                }
                .padding(.vertical, 5)
                .background(isTaskAvailable(task) ? Color.clear : Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .onAppear {
                loadTasksFromDocumentsDirectory()
            }
            .navigationTitle("Task List")
            .sheet(isPresented: Binding<Bool>(
                get: { isEditPresented && selectedTask != nil || isAddPresented },
                set: { newValue in
                    isEditPresented = newValue
                    isAddPresented = newValue
                }
            )) {
                if isAddPresented {
                    EditTaskView(task: $newTask, onSave: {
                        tasks.append(newTask)
                        saveTasksToDocumentsDirectory()
                        isAddPresented = false
                    }, isNewTask: true)
                } else if let task = selectedTask, let taskBinding = taskEditingSetup(for: task) {
                    EditTaskView(task: taskBinding, onSave: {
                        isEditPresented = false
                    })
                } else {
                    Text("No task found to edit")
                        .foregroundColor(.red)
                        .font(.headline)
                        .padding()
                }
            }
            
            // Display deletion message if there is one
            if let deletionMessage = deletionMessage, !deletionMessage.isEmpty {
                Text(deletionMessage)
                    .foregroundColor(.red)
                    .font(.headline)
                    .padding(.top, 10)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.deletionMessage = ""
                        }
                    }
            }
        }
        .padding()
    }
    
    // A function to handle the debugging and task retrieval
    func taskEditingSetup(for task: CustomTask) -> Binding<CustomTask>? {
        if let taskIndex = tasks.firstIndex(where: { $0.UUID == task.UUID }) {
            return Binding(
                get: { tasks[taskIndex] },
                set: {
                    tasks[taskIndex] = $0
                    saveTasksToDocumentsDirectory()
                }
            )
        } else {
            return nil
        }
    }
    
    // Delete task from the list and save to JSON
    private func deleteTask(_ task: CustomTask) {
        if let taskIndex = tasks.firstIndex(where: { $0.UUID == task.UUID }) {
            let taskName = tasks[taskIndex].taskName
            tasks.remove(at: taskIndex)
            saveTasksToDocumentsDirectory()
            deletionMessage = "\"\(taskName)\" deleted"
            isEditPresented = false // Ensure the edit sheet doesn't appear
            isAddPresented = false
        }
    }
    
    // Load tasks from the JSON file in the documents directory
    private func loadTasksFromDocumentsDirectory() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("FullTaskListv2.json")
        do {
            let data = try Data(contentsOf: fileURL)
            tasks = try JSONDecoder().decode([CustomTask].self, from: data)
        } catch {
            print("Failed to load tasks from JSON: \(error)")
        }
    }
    
    // Save tasks back to the JSON file in the documents directory
    private func saveTasksToDocumentsDirectory() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("FullTaskListv2.json")
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL)
            print("Successfully saved tasks to JSON.")
        } catch {
            print("Failed to save tasks to JSON: \(error)")
        }
    }
    
    // Reset all lastCompleted dates in the JSON file
    private func resetAllLastCompletedDates() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("FullTaskListv2.json")
        do {
            var loadedTasks = try JSONDecoder().decode([CustomTask].self, from: Data(contentsOf: fileURL))
            
            for i in 0..<loadedTasks.count {
                loadedTasks[i].lastCompleted = ""
            }
            
            let data = try JSONEncoder().encode(loadedTasks)
            try data.write(to: fileURL)
            tasks = loadedTasks // Update the tasks in the view
        } catch {
            print("Failed to reset lastCompleted dates: \(error)")
        }
    }
    
    // Get the documents directory URL
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // Sorting logic based on selected option
    private var sortedTasks: [CustomTask] {
        switch selectedSortOption {
        case .alphabeticalAZ:
            return tasks.sorted { $0.taskName < $1.taskName }
        case .lastCompletedAscending:
            return tasks.sorted { ($0.lastCompleted ?? "") < ($1.lastCompleted ?? "") }
        case .lastCompletedDescending:
            return tasks.sorted { ($0.lastCompleted ?? "") > ($1.lastCompleted ?? "") }
        case .repetitionIntervalAscending:
            return tasks.sorted { ($0.repetitionInterval ?? 0) < ($1.repetitionInterval ?? 0) }
        case .repetitionIntervalDescending:
            return tasks.sorted { ($0.repetitionInterval ?? 0) > ($1.repetitionInterval ?? 0) }
        case .timeUntilDue:
            return tasks.sorted(by: taskDueSoonest)
        case .durationAscending:
            return tasks.sorted { $0.minDuration < $1.minDuration }
        case .durationDescending:
            return tasks.sorted { $0.minDuration > $1.minDuration }
        }
    }
    
    // Function to sort tasks by their due time
    private func taskDueSoonest(_ task1: CustomTask, _ task2: CustomTask) -> Bool {
        let dueDate1 = taskDueDate(task1)
        let dueDate2 = taskDueDate(task2)
        return dueDate1 < dueDate2
    }
    
    // Calculate due date for a task
    private func taskDueDate(_ task: CustomTask) -> Date {
        guard let lastCompleted = task.lastCompleted?.toDate(),
              let interval = task.repetitionInterval else {
            return Date.distantPast // If no lastCompleted, it's considered overdue
        }
        return lastCompleted.addingTimeInterval(TimeInterval(interval))
    }
    
    // Check if a task is available to be scheduled
    private func isTaskAvailable(_ task: CustomTask) -> Bool {
        guard let lastCompleted = task.lastCompleted?.toDate(),
              let interval = task.repetitionInterval else {
            return true // If no lastCompleted or interval, it's available
        }
        let timeSinceCompletion = Date().timeIntervalSince(lastCompleted)
        return timeSinceCompletion > TimeInterval(interval)
    }
    
    // Helper methods
    func formattedEssentiality(_ essentiality: Int?) -> String {
        switch essentiality {
        case 3:
            return "Essential"
        case 2:
            return "Core"
        case 1:
            return "Non-essential"
        default:
            return "Unknown"
        }
    }
    
    func formattedDuration(min: Int, max: Int) -> String {
        if min == max {
            return "\(min / 60) min"
        } else {
            return "\(min / 60)-\(max / 60) min"
        }
    }
    
    func formattedRepetitionInterval(_ interval: Int?) -> String {
        guard let interval = interval, interval > 0 else {
            return "Every day"
        }
        
        if interval < 86400 {
            return "\(interval / 3600) hours"
        } else if interval < 604800 {
            return "\(interval / 86400) days"
        } else {
            return "\(interval / 604800) weeks"
        }
    }
    
    func formattedLastCompleted(_ lastCompleted: String?) -> String {
        guard let lastCompleted = lastCompleted, !lastCompleted.isEmpty else {
            return "Never"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        
        if let date = formatter.date(from: lastCompleted) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        } else {
            return "Invalid date"
        }
    }
    
    func formattedTimeUntilDue(_ task: CustomTask) -> String {
        guard let lastCompleted = task.lastCompleted,
              let interval = task.repetitionInterval,
              interval > 0,
              let lastCompletedDate = lastCompleted.toDate() else {
            return "Today"
        }
        
        let dueDate = lastCompletedDate.addingTimeInterval(TimeInterval(interval))
        let timeRemaining = dueDate.timeIntervalSince(Date())
        
        if timeRemaining <= 0 {
            return "Overdue"
        } else if timeRemaining < 86400 {
            let hours = Int(timeRemaining / 3600)
            return "\(hours) hours"
        } else if timeRemaining < 604800 {
            let days = Int(timeRemaining / 86400)
            return "\(days) days"
        } else {
            let weeks = Int(timeRemaining / 604800)
            return "\(weeks) weeks"
        }
    }
    
}
