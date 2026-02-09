import SwiftUI
import CoreData
import AVFoundation

enum TempRoutineStorage {
    static let customTaskNamesKey = "tempRoutineCustomTaskNames"
    static let selectedTaskIdsKey = "tempRoutineSelectedTaskIds"

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: customTaskNamesKey)
        defaults.removeObject(forKey: selectedTaskIdsKey)
    }
}

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
    @State private var expandedRoutineIds: Set<UUID> = []
    @State private var routineSearchText: String = ""

    // Use SceneStorage to persist custom tasks across app switches
    @SceneStorage(TempRoutineStorage.customTaskNamesKey) private var persistedCustomTaskNames: String = ""
    @SceneStorage(TempRoutineStorage.selectedTaskIdsKey) private var persistedSelectedTaskIds: String = ""
    
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

        // For tasks with repetition intervals less than 24 hours,
        // they should only be eligible when actually due
        if task.repetitionInterval < 86400 {
            // Strict timing: eligible only if due time has passed
            return now >= dueDate
        }

        // For longer intervals (>= 24 hours), eligible from midnight of the due date
        let dueDateStartOfDay = calendar.startOfDay(for: dueDate)
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
                            customTasks.removeAll()
                            expandedRoutineIds.removeAll()
                            saveCustomTasksToStorage()
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
                    routineSearchText = ""
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
            .onAppear {
                restoreFromStorage()
            }
            .onChange(of: selectedTaskIds) { _, _ in
                saveCustomTasksToStorage()
            }
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
                                
                                Text("\(task.duration) min")
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
    
    private func filteredRoutines() -> [CDRoutine] {
        if routineSearchText.isEmpty {
            return Array(cdRoutines)
        }
        return cdRoutines.filter { routine in
            routine.name?.localizedCaseInsensitiveContains(routineSearchText) ?? false
        }
    }

    private func sortedTasks(for routine: CDRoutine) -> [CDRoutineTask] {
        guard let routineTasks = routine.taskRelations?.allObjects as? [CDRoutineTask] else { return [] }
        return routineTasks.sorted { $0.order < $1.order }
    }

    private func dueTaskCount(for routine: CDRoutine) -> Int {
        sortedTasks(for: routine).filter { rt in
            guard let task = rt.task else { return false }
            return isDueForCompletion(task)
        }.count
    }

    private func addAllDueTasks(from routine: CDRoutine) {
        for routineTask in sortedTasks(for: routine) {
            guard let task = routineTask.task, isDueForCompletion(task) else { continue }
            guard let taskId = task.uuid, !selectedTaskIds.contains(taskId) else { continue }
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

    @ViewBuilder
    private func routineTaskRow(for task: CDTask) -> some View {
        let isDue = isDueForCompletion(task)
        let isSelected = selectedTaskIds.contains(task.uuid ?? UUID())

        HStack {
            Button(action: {
                toggleTaskSelection(task)
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(.blue)
                    .imageScale(.large)
            }
            .buttonStyle(BorderlessButtonStyle())

            VStack(alignment: .leading) {
                Text(task.taskName ?? "")
                    .font(.body)

                HStack(spacing: 8) {
                    Text(isDue ? "Due" : "Not due")
                        .font(.caption)
                        .foregroundColor(isDue ? .green : .orange)

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
        .padding(.leading, 16)
        .padding(.vertical, 6)
        .opacity(isDue ? 1.0 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleTaskSelection(task)
        }
    }

    @ViewBuilder
    private func routineSection(for routine: CDRoutine) -> some View {
        let routineUUID = routine.uuid ?? UUID()
        let isExpanded = expandedRoutineIds.contains(routineUUID)
        let tasks = sortedTasks(for: routine)
        let totalCount = tasks.count
        let dueCount = dueTaskCount(for: routine)

        VStack(spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedRoutineIds.remove(routineUUID)
                    } else {
                        expandedRoutineIds.insert(routineUUID)
                    }
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name ?? "")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text("\(totalCount) tasks • \(dueCount) due")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if dueCount > 0 {
                        Button(action: {
                            addAllDueTasks(from: routine)
                        }) {
                            Text("Add All Due")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal)

            // Expanded tasks
            if isExpanded {
                ForEach(tasks, id: \.objectID) { routineTask in
                    if let task = routineTask.task {
                        routineTaskRow(for: task)
                    }
                }
            }
        }
    }

    private var routineTemplateView: some View {
        VStack(spacing: 0) {
            // Search bar for routines
            SearchBar(text: $routineSearchText)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Browse routines:")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    ForEach(filteredRoutines(), id: \.objectID) { routine in
                        routineSection(for: routine)
                    }

                    if filteredRoutines().isEmpty && !routineSearchText.isEmpty {
                        Text("No routines found matching '\(routineSearchText)'")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
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

        // Save custom tasks to persistent storage
        saveCustomTasksToStorage()
    }
    
    private func removeCustomTask(_ task: TempRoutineTask) {
        customTasks.removeAll { $0.id == task.id }
        selectedTasks.removeAll { $0.id == task.id }
        saveCustomTasksToStorage()
    }

    private func saveCustomTasksToStorage() {
        // Save custom tasks as JSON array with name and duration
        let taskDicts = customTasks.map { ["name": $0.name, "duration": "\($0.duration)"] }
        if let jsonData = try? JSONSerialization.data(withJSONObject: taskDicts),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            persistedCustomTaskNames = jsonString
        }

        // Save all selected task IDs (both custom and from existing)
        let selectedIds = selectedTaskIds.map { $0.uuidString }.joined(separator: "|")
        persistedSelectedTaskIds = selectedIds
    }

    private func restoreFromStorage() {
        // Only restore if we don't already have tasks (prevents duplication)
        guard selectedTasks.isEmpty && customTasks.isEmpty else {
            logger.info("Skipping restore - tasks already exist (selectedTasks: \(selectedTasks.count), customTasks: \(customTasks.count))")
            return
        }

        // Restore custom tasks
        if !persistedCustomTaskNames.isEmpty {
            let stored = persistedCustomTaskNames.trimmingCharacters(in: .whitespacesAndNewlines)
            if stored.hasPrefix("["),
               let jsonData = stored.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] {
                // New JSON format
                customTasks = arr.map { dict in
                    TempRoutineTask(
                        name: dict["name"] ?? "",
                        duration: Int(dict["duration"] ?? "10") ?? 10,
                        isFromExisting: false
                    )
                }
            } else {
                // Legacy pipe-separated format
                let taskNames = stored.split(separator: "|").map { String($0) }
                customTasks = taskNames.map { name in
                    TempRoutineTask(
                        name: name,
                        duration: 10,
                        isFromExisting: false
                    )
                }
            }
            selectedTasks.append(contentsOf: customTasks)
            logger.info("Restored \(customTasks.count) custom tasks from storage")
        }

        // Restore selected task IDs for existing tasks
        if !persistedSelectedTaskIds.isEmpty {
            let idStrings = persistedSelectedTaskIds.split(separator: "|").map { String($0) }
            let restoredIds = Set(idStrings.compactMap { UUID(uuidString: $0) })

            // Only add IDs that aren't already in selectedTaskIds
            for id in restoredIds {
                if !selectedTaskIds.contains(id) {
                    selectedTaskIds.insert(id)

                    // Also restore the corresponding task to selectedTasks if it exists
                    if let cdTask = cdTasks.first(where: { $0.uuid == id }) {
                        let tempTask = TempRoutineTask(
                            name: cdTask.taskName ?? "",
                            duration: Int(cdTask.minDuration),
                            isFromExisting: true,
                            originalTask: cdTask
                        )
                        selectedTasks.append(tempTask)
                    }
                }
            }
            logger.info("Restored \(restoredIds.count) selected task IDs from storage")
        }
    }
    
    private func parseBulkTaskLine(_ line: String) -> (name: String, duration: Int) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Match parenthetical time at end of line
        // Patterns: (15), (15 min), (15m), (2 hours), (2h), (1h30m), (1h 30m), (90 min), (90m)
        let pattern = #"\(\s*(?:(\d+)\s*h(?:ours?)?(?:\s*(\d+)\s*m(?:in(?:utes?)?)?)?|(\d+)\s*(?:hours?)|(\d+)\s*m(?:in(?:utes?)?)?|(\d+))\s*\)\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (trimmed, 10)
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            return (trimmed, 10)
        }

        var duration = 10

        // Group 1: hours in compound (e.g., "1h30m" -> group1=1, group2=30)
        // Group 2: minutes in compound
        // Group 3: standalone hours (e.g., "2 hours")
        // Group 4: standalone minutes (e.g., "15 min", "90m")
        // Group 5: bare number (e.g., "15")

        if let g1Range = Range(match.range(at: 1), in: trimmed), let hours = Int(trimmed[g1Range]) {
            duration = hours * 60
            if let g2Range = Range(match.range(at: 2), in: trimmed), let mins = Int(trimmed[g2Range]) {
                duration += mins
            }
        } else if let g3Range = Range(match.range(at: 3), in: trimmed), let hours = Int(trimmed[g3Range]) {
            duration = hours * 60
        } else if let g4Range = Range(match.range(at: 4), in: trimmed), let mins = Int(trimmed[g4Range]) {
            duration = mins
        } else if let g5Range = Range(match.range(at: 5), in: trimmed), let mins = Int(trimmed[g5Range]) {
            duration = mins
        }

        // Strip the parenthetical from the task name
        let matchRange = Range(match.range, in: trimmed)!
        let name = String(trimmed[trimmed.startIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        return (name.isEmpty ? trimmed : name, max(1, duration))
    }

    private func processBulkTasks() {
        // Split the bulk text by newlines and process each non-empty line as a task
        let lines = bulkTaskText.split(separator: "\n")

        for line in lines {
            let lineStr = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !lineStr.isEmpty {
                let parsed = parseBulkTaskLine(lineStr)
                let tempTask = TempRoutineTask(
                    name: parsed.name,
                    duration: parsed.duration,
                    isFromExisting: false
                )
                customTasks.append(tempTask)
                selectedTasks.append(tempTask)
            }
        }

        // Clear the bulk text after processing
        bulkTaskText = ""
        showBulkEntry = false

        // Save to persistent storage
        saveCustomTasksToStorage()
    }
    
    private func proceedToTimeAllocation() {
        navigationPath.append("timeAllocation")
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
                isFromExisting: task.isFromExisting,
                prepTime: Int(task.originalTask?.prepTime ?? 0)
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

// MARK: - OpenAI Service

actor OpenAIService {
    enum OpenAIError: LocalizedError {
        case noAPIKey
        case networkError(String)
        case emptyTranscription
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No OpenAI API key configured. Add one in Settings > AI Features."
            case .networkError(let msg): return "Network error: \(msg)"
            case .emptyTranscription: return "No speech was detected in the recording."
            case .invalidResponse: return "Received an invalid response from OpenAI."
            }
        }
    }

    func transcribe(audioURL: URL, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: audioURL)

        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.networkError(errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String, !text.isEmpty else {
            throw OpenAIError.emptyTranscription
        }

        return text
    }

    func formatAsTaskList(transcription: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let systemPrompt = """
        You are a task list formatter. Convert the user's spoken input into a clean task list.
        Rules:
        - One task per line
        - If the user mentions a time estimate, put it in parentheses as minutes at the end of the line
        - Convert hours to minutes: "2 hours" -> (120), "1 hour 30 minutes" -> (90)
        - If no time is mentioned for a task, omit the parenthetical
        - Capitalize the first letter of each task
        - Remove filler words like "um", "uh", "like", "so"
        - Do not add any extra text, headers, or numbering
        Example input: "buy groceries about 30 minutes, clean the house two hours, call mom"
        Example output:
        Buy groceries (30)
        Clean the house (120)
        Call mom
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcription]
            ],
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.networkError(errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bulk Task Entry View

struct BulkTaskEntryView: View {
    @Binding var bulkTaskText: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settingsManager = SettingsManager.shared

    // Voice recording state
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false

    private let openAIService = OpenAIService()

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Enter tasks, one per line:")
                    .font(.headline)
                    .padding(.top)

                Text("Add time in parentheses: (15) = 15 min, (2h) = 2 hours, (1h30m) = 90 min. No time = 10 min default.")
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
                        Text("Buy groceries (30)\nClean house (2 hours)\nCall mom\n...")
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal)

                // Voice input section
                VStack(spacing: 8) {
                    if settingsManager.openAIAPIKey.isEmpty {
                        HStack {
                            Image(systemName: "mic.slash")
                                .foregroundColor(.secondary)
                            Text("Voice input requires an OpenAI API key (Settings > AI Features)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    } else {
                        HStack(spacing: 16) {
                            Button(action: {
                                if isRecording {
                                    stopRecording()
                                } else {
                                    startRecording()
                                }
                            }) {
                                HStack {
                                    if isProcessing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                            .imageScale(.large)
                                    }
                                    Text(isRecording ? "Stop Recording" : isProcessing ? "Processing..." : "Voice Input")
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isRecording ? Color.red : isProcessing ? Color.orange : Color.purple)
                                .cornerRadius(20)
                            }
                            .disabled(isProcessing)

                            if isRecording {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                    .opacity(isRecording ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("Cancel") {
                        cleanupRecording()
                        dismiss()
                    }
                    .foregroundColor(.red)

                    Button(action: {
                        cleanupRecording()
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
            .alert("Voice Input Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .onDisappear {
                cleanupRecording()
            }
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()

        // Check/request microphone permission
        switch session.recordPermission {
        case .denied:
            errorMessage = "Microphone access denied. Please enable it in Settings > Privacy > Microphone."
            showError = true
            return
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.beginRecording()
                    } else {
                        self.errorMessage = "Microphone access is required for voice input."
                        self.showError = true
                    }
                }
            }
            return
        case .granted:
            break
        @unknown default:
            break
        }

        beginRecording()
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            showError = true
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("voice_task_\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            audioRecorder = recorder
            isRecording = true
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            showError = true
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        guard let url = recordingURL else { return }

        isProcessing = true
        let apiKey = settingsManager.openAIAPIKey

        Task {
            do {
                let transcription = try await openAIService.transcribe(audioURL: url, apiKey: apiKey)
                let formatted = try await openAIService.formatAsTaskList(transcription: transcription, apiKey: apiKey)

                await MainActor.run {
                    // Append to existing text
                    if !bulkTaskText.isEmpty && !bulkTaskText.hasSuffix("\n") {
                        bulkTaskText += "\n"
                    }
                    bulkTaskText += formatted
                    isProcessing = false
                    deleteRecordingFile(url)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                    deleteRecordingFile(url)
                }
            }
        }
    }

    private func cleanupRecording() {
        if isRecording {
            audioRecorder?.stop()
            audioRecorder = nil
            isRecording = false
        }
        if let url = recordingURL {
            deleteRecordingFile(url)
        }
    }

    private func deleteRecordingFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
    }
}

struct TempRoutineEntryView_Previews: PreviewProvider {
    static var previews: some View {
        TempRoutineEntryView()
    }
}