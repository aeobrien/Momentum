import SwiftUI
import CoreData

enum TempRoutineFilter: CaseIterable {
    case custom
    case due
    case all
    case routineTemplate
    
    var description: String {
        switch self {
        case .custom:
            return "Custom Tasks"
        case .due:
            return "Due Tasks"
        case .all:
            return "All Tasks"
        case .routineTemplate:
            return "From Routine"
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

// No longer needed with the new navigation structure
// struct TaskWithDuration: Identifiable {
//     let id = UUID()
//     let name: String
//     let duration: Int
// }

struct TempRoutineEntryView: View {
    let onStartTasks: (([TempTask]) -> Void)?
    
    @State private var selectedTasks: [TempRoutineTask] = []
    @State private var customTaskText: String = ""
    @State private var customTasks: [TempRoutineTask] = []
    @State private var selectedFilter: TempRoutineFilter = .custom
    @State private var selectedTaskIds: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var bulkTaskText: String = ""
    @State private var showBulkEntry: Bool = false
    @State private var navigationPath = NavigationPath()
    @State private var selectedRoutine: CDRoutine? = nil
    @State private var routineTemplateTasks: [TempRoutineTask] = []
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var cdTasks: FetchedResults<CDTask>
    @FetchRequest private var cdRoutines: FetchedResults<CDRoutine>
    
    private let logger = AppLogger.create(subsystem: "com.app.TempRoutineEntryView", category: "UI")
    
    init(onStartTasks: (([TempTask]) -> Void)? = nil) {
        self.onStartTasks = onStartTasks
        
        let taskRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        taskRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        _cdTasks = FetchRequest(fetchRequest: taskRequest)
        
        let routineRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        routineRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDRoutine.name, ascending: true)]
        _cdRoutines = FetchRequest(fetchRequest: routineRequest)
    }
    
    private func isDueForCompletion(_ task: CDTask) -> Bool {
        guard let lastCompleted = task.lastCompleted else {
            return true
        }

        if task.repetitionInterval == 0 {
            return !Calendar.current.isDateInToday(lastCompleted)
        }

        let now = Date()
        let calendar = Calendar.current

        // Calculate when the task will be due based on the interval
        let dueDate = lastCompleted.addingTimeInterval(TimeInterval(task.repetitionInterval))

        // Get the start of the day when the task will be due
        let dueDateStartOfDay = calendar.startOfDay(for: dueDate)

        // If we're past the start of the due day, the task is due
        // This allows tasks to be completed from midnight on their due date
        return now >= dueDateStartOfDay
    }
    
    private func filteredTasks() -> [CDTask] {
        let tasks: [CDTask]
        switch selectedFilter {
        case .custom:
            return []
        case .routineTemplate:
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
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Task counter at top, visible in all tabs
                if !selectedTasks.isEmpty {
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
                    .background(Color(.systemGray6))

                    Divider()
                }

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
                } else if selectedFilter == .routineTemplate {
                    routineTemplateView
                } else {
                    existingTasksView
                }
                
                // Next button
                VStack(spacing: 0) {
                    Divider()

                    Button(action: {
                        navigationPath.append("reorder")
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
            .navigationDestination(for: String.self) { destination in
                if destination == "reorder" {
                    TempRoutineReorderViewIntegrated(
                        tasks: $selectedTasks,
                        navigationPath: $navigationPath
                    )
                } else if destination == "timeAllocation" {
                    TempRoutineTimeAllocationViewIntegrated(
                        tasks: selectedTasks,
                        onStartTasks: onStartTasks
                    )
                }
            }
            .sheet(isPresented: $showBulkEntry) {
                BulkTaskEntryView(bulkTaskText: $bulkTaskText, onConfirm: processBulkTasks)
            }
        }
    }
    
    private var customTasksView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Add custom tasks:")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            showBulkEntry = true
                        }) {
                            Label("Bulk Add", systemImage: "text.alignleft")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
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

                    // Show selected tasks from other tabs (read-only)
                    let otherSelectedTasks = selectedTasks.filter { task in
                        task.isFromExisting && !customTasks.contains(where: { custom in custom.id == task.id })
                    }
                    if !otherSelectedTasks.isEmpty {
                        Divider()
                            .padding(.vertical, 8)

                        Text("Selected from other tabs:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(otherSelectedTasks) { task in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)

                                Text(task.name)
                                    .font(.body)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("\(task.duration) min")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
    
    private var routineTemplateView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select a routine as template:")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    if selectedRoutine == nil {
                        // Show routine picker
                        ForEach(cdRoutines) { routine in
                            Button(action: {
                                loadRoutineTemplate(routine)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(routine.name ?? "")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        
                                        if let tasks = routine.taskRelations?.allObjects as? [CDRoutineTask] {
                                            Text("\(tasks.count) tasks")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        // Show selected routine tasks
                        HStack {
                            Text("Template: \(selectedRoutine?.name ?? "")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Change") {
                                selectedRoutine = nil
                                routineTemplateTasks.removeAll()
                                selectedTasks.removeAll(where: { routineTemplateTasks.contains($0) })
                            }
                            .font(.subheadline)
                        }
                        .padding(.horizontal)
                        
                        Text("Tasks from routine (tap to toggle):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ForEach(routineTemplateTasks) { task in
                            HStack {
                                Button(action: {
                                    toggleTemplateTaskSelection(task)
                                }) {
                                    Image(systemName: selectedTasks.contains(where: { $0.id == task.id }) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(.blue)
                                        .imageScale(.large)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                
                                VStack(alignment: .leading) {
                                    Text(task.name)
                                        .font(.body)
                                    
                                    HStack {
                                        Text("\(task.duration) min")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if task.isFromExisting {
                                            Text("• Tracked")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleTemplateTaskSelection(task)
                            }
                        }
                        
                        // Allow adding custom tasks to template
                        Divider()
                            .padding(.vertical)
                        
                        Text("Add custom tasks to template:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
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
                    }
                    
                    Spacer(minLength: 20)
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
    
    private func processBulkTasks() {
        // Split the bulk text by newlines and process each non-empty line as a task
        let lines = bulkTaskText.split(separator: "\n")
        
        for line in lines {
            let taskName = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !taskName.isEmpty {
                let tempTask = TempRoutineTask(
                    name: taskName,
                    duration: 10, // Default 10 minutes for bulk-added tasks
                    isFromExisting: false
                )
                customTasks.append(tempTask)
                selectedTasks.append(tempTask)
            }
        }
        
        // Clear the bulk text after processing
        bulkTaskText = ""
        showBulkEntry = false
    }
    
    private func proceedToTimeAllocation() {
        navigationPath.append("timeAllocation")
    }
    
    private func loadRoutineTemplate(_ routine: CDRoutine) {
        selectedRoutine = routine
        routineTemplateTasks.removeAll()
        
        // Load tasks from the routine through CDRoutineTask relationships
        if let routineTasks = routine.taskRelations?.allObjects as? [CDRoutineTask] {
            // Sort by order
            let sortedRoutineTasks = routineTasks.sorted { $0.order < $1.order }
            
            for routineTask in sortedRoutineTasks {
                if let task = routineTask.task {
                    let tempTask = TempRoutineTask(
                        name: task.taskName ?? "",
                        duration: Int(task.minDuration),
                        isFromExisting: true,
                        originalTask: task
                    )
                    routineTemplateTasks.append(tempTask)
                    selectedTasks.append(tempTask)
                }
            }
        }
        
        logger.info("Loaded routine template '\(routine.name ?? "")' with \(routineTemplateTasks.count) tasks")
    }
    
    private func toggleTemplateTaskSelection(_ task: TempRoutineTask) {
        if let index = selectedTasks.firstIndex(where: { $0.id == task.id }) {
            selectedTasks.remove(at: index)
        } else {
            selectedTasks.append(task)
        }
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

// These structures are no longer needed but kept for backwards compatibility
// Can be removed in a future update once all references are cleaned up

// Integrated reorder view for navigation stack
struct TempRoutineReorderViewIntegrated: View {
    @Binding var tasks: [TempRoutineTask]
    @Binding var navigationPath: NavigationPath
    
    var body: some View {
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
                navigationPath.append("timeAllocation")
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
        .navigationBarBackButtonHidden(false)
    }
}

// Integrated time allocation view for navigation stack
struct TempRoutineTimeAllocationViewIntegrated: View {
    let tasks: [TempRoutineTask]
    let onStartTasks: (([TempTask]) -> Void)?
    @State private var taskDurations: [Int] = []
    
    private let logger = AppLogger.create(subsystem: "com.app.TempRoutineTimeAllocationViewIntegrated", category: "UI")
    
    init(tasks: [TempRoutineTask], onStartTasks: (([TempTask]) -> Void)?) {
        self.tasks = tasks
        self.onStartTasks = onStartTasks
        _taskDurations = State(initialValue: tasks.map { $0.duration })
    }
    
    var body: some View {
        VStack {
            Text("Adjust task durations if needed")
                .font(.headline)
                .padding(.top)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
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
        .navigationBarBackButtonHidden(false)
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
        logger.info("Starting temporary routine with \(tasks.count) tasks")
        
        var tempTasks: [TempTask] = []
        
        for (index, task) in tasks.enumerated() {
            let tempTask = TempTask(
                name: task.name,
                duration: taskDurations[index],
                originalTaskUUID: task.originalTask?.uuid,
                isFromExisting: task.isFromExisting
            )
            tempTasks.append(tempTask)
        }
        
        // Call the callback to pass the tasks to the parent view
        if let onStartTasks = onStartTasks {
            logger.info("Calling onStartTasks callback with \(tempTasks.count) tasks")
            onStartTasks(tempTasks)
        }
    }
}

// Bulk task entry view
struct BulkTaskEntryView: View {
    @Binding var bulkTaskText: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Enter tasks, one per line:")
                    .font(.headline)
                    .padding(.top)
                
                Text("Each task will be added with a default duration of 10 minutes. You can adjust durations later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $bulkTaskText)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    // Placeholder text when empty
                    if bulkTaskText.isEmpty {
                        Text("Task 1\nTask 2\nTask 3\n...")
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                    
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Text("Add Tasks")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bulkTaskText.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                    }
                    .disabled(bulkTaskText.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Bulk Add Tasks")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TempRoutineEntryView_Previews: PreviewProvider {
    static var previews: some View {
        TempRoutineEntryView()
    }
}