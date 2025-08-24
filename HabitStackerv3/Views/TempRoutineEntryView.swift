import SwiftUI
import CoreData

enum TempRoutineFilter: CaseIterable {
    case custom
    case due
    case all
    
    var description: String {
        switch self {
        case .custom:
            return "Custom Tasks"
        case .due:
            return "Due Tasks"
        case .all:
            return "All Tasks"
        }
    }
}

struct TempRoutineTask: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let duration: Int // in minutes
    let isFromExisting: Bool
    let originalTask: CDTask?
    
    init(name: String, duration: Int = 10, isFromExisting: Bool = false, originalTask: CDTask? = nil) {
        self.name = name
        self.duration = duration
        self.isFromExisting = isFromExisting
        self.originalTask = originalTask
    }
}

struct TaskWithDuration: Identifiable {
    let id = UUID()
    let name: String
    let duration: Int
}

struct TempRoutineEntryView: View {
    @State private var selectedTasks: [TempRoutineTask] = []
    @State private var customTaskText: String = ""
    @State private var customTasks: [TempRoutineTask] = []
    @State private var selectedFilter: TempRoutineFilter = .custom
    @State private var selectedTaskIds: Set<UUID> = []
    @State private var taskListForSheet: TempTaskListWithDurations? = nil
    @State private var showingReorderView = false
    @State private var searchText: String = ""
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var cdTasks: FetchedResults<CDTask>
    
    private let logger = AppLogger.create(subsystem: "com.app.TempRoutineEntryView", category: "UI")
    
    init() {
        let request: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        _cdTasks = FetchRequest(fetchRequest: request)
    }
    
    private func isDueForCompletion(_ task: CDTask) -> Bool {
        guard let lastCompleted = task.lastCompleted else {
            return true
        }
        
        if task.repetitionInterval == 0 {
            return !Calendar.current.isDateInToday(lastCompleted)
        }
        
        let now = Date()
        let secondsSinceCompletion = now.timeIntervalSince(lastCompleted)
        let requiredInterval = TimeInterval(task.repetitionInterval)
        return secondsSinceCompletion >= requiredInterval
    }
    
    private func filteredTasks() -> [CDTask] {
        let tasks: [CDTask]
        switch selectedFilter {
        case .custom:
            return []
        case .due:
            tasks = Array(cdTasks.filter { isDueForCompletion($0) })
        case .all:
            tasks = Array(cdTasks)
        }
        
        // Apply search filter if search text is not empty
        let filteredBySearch = searchText.isEmpty ? tasks : tasks.filter { task in
            task.taskName?.localizedCaseInsensitiveContains(searchText) ?? false
        }
        
        return filteredBySearch.sorted { ($0.taskName ?? "") < ($1.taskName ?? "") }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Three-tab picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(TempRoutineFilter.allCases, id: \.self) { filter in
                        Text(filter.description).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: selectedFilter) { _ in
                    // Clear search when switching tabs
                    searchText = ""
                }
                
                // Content based on selected tab
                if selectedFilter == .custom {
                    customTasksView
                } else {
                    existingTasksView
                }
                
                // Selected tasks summary and next button
                VStack(spacing: 0) {
                    if !selectedTasks.isEmpty {
                        Divider()
                        
                        HStack {
                            Text("Selected: \(selectedTasks.count) task\(selectedTasks.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Clear All") {
                                selectedTasks.removeAll()
                                selectedTaskIds.removeAll()
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    
                    Button(action: {
                        showingReorderView = true
                    }) {
                        Text("Next: Arrange Tasks")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedTasks.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                    }
                    .disabled(selectedTasks.isEmpty)
                    .padding()
                }
            }
            .navigationTitle("Temporary Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingReorderView) {
                TempRoutineReorderView(tasks: $selectedTasks, onComplete: proceedToTimeAllocation)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $taskListForSheet) { taskList in
                TempRoutineTimeAllocationViewWithDurations(tasksWithDurations: taskList.tasks)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    private var customTasksView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add custom tasks:")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    HStack {
                        TextField("Enter task name", text: $customTaskText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addCustomTask()
                            }
                        
                        Button(action: addCustomTask) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .imageScale(.large)
                        }
                        .disabled(customTaskText.isEmpty)
                    }
                    .padding(.horizontal)
                    
                    if !customTasks.isEmpty {
                        Text("Your custom tasks:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ForEach(customTasks) { task in
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                
                                Text(task.name)
                                    .font(.body)
                                
                                Spacer()
                                
                                Text("10 min")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    removeCustomTask(task)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
            }
        }
    }
    
    private var existingTasksView: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $searchText)
                .padding(.horizontal)
                .padding(.top, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select existing tasks:")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    ForEach(filteredTasks()) { task in
                        taskRow(for: task)
                    }
                    
                    if filteredTasks().isEmpty && !searchText.isEmpty {
                        Text("No tasks found matching '\(searchText)'")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func taskRow(for task: CDTask) -> some View {
        HStack {
            Button(action: {
                toggleTaskSelection(task)
            }) {
                Image(systemName: selectedTaskIds.contains(task.uuid ?? UUID()) ? "checkmark.square.fill" : "square")
                    .foregroundColor(.blue)
                    .imageScale(.large)
            }
            .buttonStyle(BorderlessButtonStyle())
            
            VStack(alignment: .leading) {
                Text(task.taskName ?? "")
                    .font(.body)
                
                HStack(spacing: 8) {
                    if isDueForCompletion(task) {
                        Text("Due")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Text("\(Int(task.minDuration)) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Circle()
                .fill(essentialityColor(task.essentiality))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleTaskSelection(task)
        }
    }
    
    private func toggleTaskSelection(_ task: CDTask) {
        guard let taskId = task.uuid else { return }
        
        if selectedTaskIds.contains(taskId) {
            selectedTaskIds.remove(taskId)
            selectedTasks.removeAll { $0.originalTask?.uuid == taskId }
        } else {
            selectedTaskIds.insert(taskId)
            let tempTask = TempRoutineTask(
                name: task.taskName ?? "",
                duration: Int(task.minDuration),
                isFromExisting: true,
                originalTask: task
            )
            selectedTasks.append(tempTask)
        }
    }
    
    private func addCustomTask() {
        guard !customTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let tempTask = TempRoutineTask(
            name: customTaskText.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: 10, // Default 10 minutes for custom tasks
            isFromExisting: false
        )
        customTasks.append(tempTask)
        selectedTasks.append(tempTask)
        customTaskText = ""
    }
    
    private func removeCustomTask(_ task: TempRoutineTask) {
        customTasks.removeAll { $0.id == task.id }
        selectedTasks.removeAll { $0.id == task.id }
    }
    
    private func proceedToTimeAllocation() {
        let tasksWithDurations = selectedTasks.map { task in
            TaskWithDuration(name: task.name, duration: task.duration)
        }
        logger.info("Proceeding with \(tasksWithDurations.count) tasks to time allocation")
        taskListForSheet = TempTaskListWithDurations(tasks: tasksWithDurations)
        showingReorderView = false
    }
    
    private func essentialityColor(_ value: Int16) -> Color {
        switch value {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .gray
        }
    }
}

// Wrapper for sheet presentation with durations
struct TempTaskListWithDurations: Identifiable {
    let id = UUID()
    let tasks: [TaskWithDuration]
}

struct TempRoutineReorderView: View {
    @Binding var tasks: [TempRoutineTask]
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Drag to reorder tasks")
                    .font(.headline)
                    .padding()
                
                List {
                    ForEach(tasks) { task in
                        HStack {
                            Image(systemName: "line.horizontal.3")
                                .foregroundColor(.gray)
                            
                            Image(systemName: task.isFromExisting ? "checkmark.circle.fill" : "plus.circle.fill")
                                .foregroundColor(task.isFromExisting ? .green : .blue)
                            
                            Text(task.name)
                            
                            Spacer()
                            
                            Text("\(task.duration) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        tasks.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .environment(\.editMode, .constant(.active))
                
                Button(action: {
                    onComplete()
                    dismiss()
                }) {
                    Text("Confirm Order")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Arrange Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// New view that accepts tasks with durations
struct TempRoutineTimeAllocationViewWithDurations: View {
    let tasksWithDurations: [TaskWithDuration]
    @State private var taskDurations: [Int] = []
    @State private var showRunner = false
    @StateObject private var runnerWrapper = TempRunnerWrapper()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    private let logger = AppLogger.create(subsystem: "com.app.TempRoutineTimeAllocationViewWithDurations", category: "UI")
    
    init(tasksWithDurations: [TaskWithDuration]) {
        self.tasksWithDurations = tasksWithDurations
        _taskDurations = State(initialValue: tasksWithDurations.map { $0.duration })
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Adjust task durations if needed")
                    .font(.headline)
                    .padding(.top)
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Array(tasksWithDurations.enumerated()), id: \.offset) { index, task in
                            HStack {
                                Text(task.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    TextField("\(task.duration)", value: $taskDurations[index], format: .number)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 60)
                                        .keyboardType(.numberPad)
                                    
                                    Text("min")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        Text("Total time:")
                            .font(.headline)
                        Spacer()
                        Text(formatTotalDuration())
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }
                
                Button(action: startTempRoutine) {
                    Text("Start Routine")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Set Task Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showRunner) {
                Group {
                    if let runner = runnerWrapper.runner {
                        TempRoutineRunnerView(runner: runner)
                    } else {
                        VStack {
                            Text("Error: Runner not initialized")
                                .foregroundColor(.red)
                            Button("Dismiss") {
                                showRunner = false
                            }
                            .padding()
                        }
                    }
                }
            }
        }
    }
    
    private func formatTotalDuration() -> String {
        let totalMinutes = taskDurations.reduce(0, +)
        if totalMinutes < 60 {
            return "\(totalMinutes) minutes"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
    
    private func startTempRoutine() {
        logger.info("Starting temporary routine with \(tasksWithDurations.count) tasks")
        
        var tempTasks: [TempTask] = []
        
        for (index, task) in tasksWithDurations.enumerated() {
            let tempTask = TempTask(
                name: task.name,
                duration: taskDurations[index]
            )
            tempTasks.append(tempTask)
        }
        
        let runner = TempRoutineRunner(tasks: tempTasks)
        runnerWrapper.runner = runner
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.runnerWrapper.runner != nil {
                showRunner = true
                logger.info("Presenting TempRoutineRunnerView")
            }
        }
    }
}

struct TempRoutineEntryView_Previews: PreviewProvider {
    static var previews: some View {
        TempRoutineEntryView()
    }
}