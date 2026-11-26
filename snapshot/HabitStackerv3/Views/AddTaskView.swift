import SwiftUI
import SwiftSoup
import UniformTypeIdentifiers

// Note: ChecklistItemsWrapper and related views have been removed
// The checklist functionality is now integrated directly into AddTaskView
// using @State for the single source of truth

/// Enum representing the essentiality levels
enum Essentiality: String, CaseIterable, Identifiable {
    case essential = "Essential"
    case core = "Core"
    case nonEssential = "Non-Essential"
    
    var id: String { self.rawValue }
    
    /// Maps each essentiality level to its corresponding integer value
    var value: Int {
        switch self {
            case .essential:
                return 3
            case .core:
                return 2
            case .nonEssential:
                return 1
        }
    }
}

/// Enum representing the units for repetition interval
enum RepetitionUnit: String, CaseIterable, Identifiable {
    case hours = "Hours"
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"
    
    var id: String { self.rawValue }
    
    /// Converts the entered value to seconds based on the selected unit
    /// - Parameter value: The numerical value entered by the user
    /// - Returns: The equivalent value in seconds, or nil if conversion is not applicable (e.g., invalid input)
    func toSeconds(value: Int) -> Int? {
        guard value > 0 else { return nil } // Ensure value is positive
        switch self {
            case .hours:
                return value * 3600 // 60 * 60
            case .days:
                return value * 86400 // 24 * 60 * 60
            case .weeks:
                return value * 604800 // 7 * 24 * 60 * 60
            case .months:
                // Using 30 days as an approximation for a month
                return value * 2592000 // 30 * 24 * 60 * 60
        }
    }

    /// Tries to find the best unit and value to represent a given interval in seconds.
    /// Defaults to days if no other unit fits well.
    /// Returns nil if the interval is 0 or negative.
    static func fromSeconds(_ seconds: Int) -> (unit: RepetitionUnit, value: Int)? {
        guard seconds > 0 else { return nil } // Cannot represent 0 or negative intervals this way

        if seconds % 2592000 == 0 {
            return (.months, seconds / 2592000)
        } else if seconds % 604800 == 0 {
            return (.weeks, seconds / 604800)
        } else if seconds % 86400 == 0 {
            return (.days, seconds / 86400)
        } else if seconds % 3600 == 0 {
            return (.hours, seconds / 3600)
        } else {
            // Fallback: represent in hours if less than a day, otherwise days (rounded down)
            if seconds < 86400 {
                 return (.hours, seconds / 3600) // Integer division rounds down
            } else {
                return (.days, seconds / 86400) // Integer division rounds down
            }
        }
    }
}

/// AddTaskView provides a form to create or edit a task
struct AddTaskView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var settingsManager = SettingsManager.shared
    let existingTask: CustomTask?
    let onSave: (CustomTask) -> Void
    
    // MARK: - State Variables
    // Task Properties
    @State private var uuid: String
    @State private var taskName: String
    @State private var selectedEssentiality: Essentiality
    @State private var isVariableDuration: Bool
    @State private var duration: String // For fixed duration
    @State private var minDuration: String // For variable duration
    @State private var maxDuration: String // For variable duration
    
    // Repetition Properties
    @State private var isRepeatDaily: Bool // New state for daily reset toggle
    @State private var repetitionInterval: String // Value for interval (e.g., "3")
    @State private var selectedRepetitionUnit: RepetitionUnit // Unit for interval (e.g., .days)
    
    // Session Task Property
    @State private var isSessionTask: Bool // New state for session task toggle
    
    // Average Time Tracking Property
    @State private var shouldTrackAverageTime: Bool // New state for average time tracking toggle
    
    // Checklist Properties
    @State private var isChecklistTask: Bool
    @State private var checklistItems: [ChecklistItem] = []
    @State private var newItemText: String = ""

    // Prep Time Property
    @State private var selectedPrepTime: Int = 0

    // UI State
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showJSONPreview: Bool = false // For clipboard import
    @State private var editMode: EditMode = .inactive
    
    // Debug
    private let viewId: UUID
    @State private var jsonPreviewContent: String = "" // For clipboard import
    @State private var wrapperCreationCount: Int = 0
    
    // Info popover states
    @State private var showTaskNameInfo = false
    @State private var showEssentialityInfo = false
    @State private var showSessionTaskInfo = false
    @State private var showTrackAverageInfo = false
    @State private var showDurationInfo = false
    @State private var showRepeatDailyInfo = false
    @State private var showRepeatIntervalInfo = false
    
    // JSON parsing helper struct that matches the expected input format
    private struct TaskInput: Codable {
        let taskName: String
        let essentiality: Int?
        let minDuration: Int
        let maxDuration: Int
        let repetitionInterval: Int? // Stored as Int (seconds) in CustomTask
        let isSessionTask: Bool? // Added for JSON import
        let shouldTrackAverageTime: Bool? // Added for JSON import
        let isChecklistTask: Bool?
        let checklistItems: [ChecklistItem]?
        let uuid: String?
        let lastCompleted: String?
        let order: Int?
        let prepTime: Int? // Prep time in seconds
    }

    // MARK: - Initializer
    init(task: CustomTask? = nil, onSave: @escaping (CustomTask) -> Void) {
        self.existingTask = task
        self.onSave = onSave
        self.viewId = UUID()
        
        print("[AddTaskView \(self.viewId)] init called - Task: \(task?.taskName ?? "New Task")")
        
        // Initialize state properties
        _uuid = State(initialValue: task?.uuid ?? UUID().uuidString)
        _taskName = State(initialValue: task?.taskName ?? "")
        _isSessionTask = State(initialValue: task?.isSessionTask ?? false)
        _shouldTrackAverageTime = State(initialValue: task?.shouldTrackAverageTime ?? true)
        _isChecklistTask = State(initialValue: task?.isChecklistTask ?? false)
        let initialChecklistItems = task?.checklistItems ?? []
        print("[AddTaskView \(self.viewId)] Initializing with \(initialChecklistItems.count) checklist items")
        
        // Initialize checklist items state
        _checklistItems = State(initialValue: initialChecklistItems)
        
        // Set essentiality
        let essentiality: Essentiality
        if let task = task, let essentialityValue = task.essentiality {
            switch essentialityValue {
            case 3:
                essentiality = .essential
            case 2:
                essentiality = .core
            case 1:
                essentiality = .nonEssential
            default:
                essentiality = .core
            }
        } else {
            essentiality = .core
        }
        _selectedEssentiality = State(initialValue: essentiality)
        
        // Set duration values
        if let task = task {
            _isVariableDuration = State(initialValue: task.minDuration != task.maxDuration)
            if task.minDuration != task.maxDuration {
                _minDuration = State(initialValue: "\(task.minDuration)")
                _maxDuration = State(initialValue: "\(task.maxDuration)")
                _duration = State(initialValue: "")
            } else {
                _duration = State(initialValue: "\(task.minDuration)")
                _minDuration = State(initialValue: "")
                _maxDuration = State(initialValue: "")
            }
        } else {
            _isVariableDuration = State(initialValue: false)
            // Set default 10 minutes for No Timers mode
            let defaultDuration = SettingsManager.shared.noTimersMode ? "10" : ""
            _duration = State(initialValue: defaultDuration)
            _minDuration = State(initialValue: "")
            _maxDuration = State(initialValue: "")
        }
        
        // Set repetition values
        if let task = task, let repetitionSeconds = task.repetitionInterval {
            if repetitionSeconds == 0 {
                _isRepeatDaily = State(initialValue: true)
                _repetitionInterval = State(initialValue: "")
                _selectedRepetitionUnit = State(initialValue: .days)
            } else if let (unit, value) = RepetitionUnit.fromSeconds(repetitionSeconds) {
                _isRepeatDaily = State(initialValue: false)
                _repetitionInterval = State(initialValue: "\(value)")
                _selectedRepetitionUnit = State(initialValue: unit)
            } else {
                _isRepeatDaily = State(initialValue: false)
                _repetitionInterval = State(initialValue: "")
                _selectedRepetitionUnit = State(initialValue: .days)
            }
        } else {
            _isRepeatDaily = State(initialValue: false)
            _repetitionInterval = State(initialValue: "")
            _selectedRepetitionUnit = State(initialValue: .days)
        }

        // Set prep time
        _selectedPrepTime = State(initialValue: task?.prepTime ?? 0)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    // --- Section 1: Task Details ---
                    Section("Task Details") {
                        // Task Name
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Task Name")
                                    .formLabelStyle()
                                Button(action: { showTaskNameInfo.toggle() }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .imageScale(.small)
                                }
                                .popover(isPresented: $showTaskNameInfo) {
                                    Text("Enter a descriptive name for your task")
                                        .padding()
                                        .frame(maxWidth: 250)
                                }
                            }
                            TextField("Enter task name", text: $taskName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(.vertical, 4)
                        
                        // Essentiality
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Essentiality")
                                    .formLabelStyle()
                                Button(action: { showEssentialityInfo.toggle() }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .imageScale(.small)
                                }
                                .popover(isPresented: $showEssentialityInfo) {
                                    Text("How important is this task? Essential tasks are prioritized first, followed by Core, then Non-Essential tasks when time is limited.")
                                        .padding()
                                        .frame(maxWidth: 250)
                                }
                            }
                            Picker("", selection: $selectedEssentiality) {
                                ForEach(Essentiality.allCases.reversed(), id: \.self) { essentiality in
                                    HStack {
                                        Circle()
                                            .fill(essentialityColor(essentiality))
                                            .frame(width: 8, height: 8)
                                        Text(essentiality.rawValue)
                                    }
                                    .tag(essentiality)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(.vertical, 4)
                        
                        // Session Task Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Session Task", isOn: $isSessionTask)
                            Text("Session tasks only appear in routines, not the main to-do list.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        // Average Time Tracking Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Track Average Completion Time", isOn: $shouldTrackAverageTime)
                            Text("Record completion times to calculate average duration for this task.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        // Checklist Task Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Checklist Task", isOn: $isChecklistTask)
                            Text("Transform this task into a checklist with multiple items to complete.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        // Checklist Items (inside Form with stable state)
                        Divider()
                            .padding(.vertical, 4)
                            .collapsible(visible: isChecklistTask)

                        // Always mounted; show/hide content only
                        Group {
                            // Add new item
                            HStack {
                                TextField("Add new item", text: $newItemText)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onSubmit {
                                        addChecklistItem()
                                    }

                                Button(action: addChecklistItem) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                                .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .collapsible(visible: isChecklistTask)

                            // The items — binding-based ForEach inside the Form section
                            ForEach($checklistItems) { $item in
                                HStack {
                                    Image(systemName: "line.horizontal.3")
                                        .foregroundStyle(.secondary)

                                    TextField("Item", text: $item.title)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())

                                    Button {
                                        checklistItems.removeAll { $0.id == item.id }
                                        renumberChecklistItems()
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .onMove(perform: moveChecklistItem)
                            .collapsible(visible: isChecklistTask)

                            if checklistItems.isEmpty {
                                Text("No items added yet")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(.vertical, 8)
                                    .collapsible(visible: isChecklistTask)
                            }
                        }
                    }
                    .onChange(of: isChecklistTask) { _, new in
                        print("[ATV] isChecklistTask -> \(new)")
                    }
                    
                    // --- Section 2: Duration (hidden in No Timers mode) ---
                    if !settingsManager.noTimersMode {
                        Section(header: HStack {
                            Text("Duration")
                            Button(action: { showDurationInfo.toggle() }) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .imageScale(.small)
                            }
                            .popover(isPresented: $showDurationInfo) {
                                Text("Specify how long the task takes. Use variable duration if the time varies depending on circumstances.")
                                    .padding()
                                    .frame(maxWidth: 250)
                            }
                        }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Variable Duration", isOn: $isVariableDuration.animation())
                                .padding(.bottom, 4) // Add padding below toggle
                            
                            if isVariableDuration {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading) {
                                        Text("Minimum (mins)")
                                            .formLabelStyle()
                                        TextField("Min", text: $minDuration)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                    }
                                    
                                    VStack(alignment: .leading) {
                                        Text("Maximum (mins)")
                                            .formLabelStyle()
                                        TextField("Max", text: $maxDuration)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                    }
                                }
                            } else {
                                VStack(alignment: .leading) {
                                    Text("Fixed Duration (mins)")
                                        .formLabelStyle()
                                    TextField("Duration", text: $duration)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    }
                    
                    // --- Section 2b: Prep Time (hidden in No Timers mode) ---
                    if !settingsManager.noTimersMode {
                        Section(header: Text("Prep Time")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Optional countdown before task starts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("Prep Time", selection: $selectedPrepTime) {
                                    Text("None").tag(0)
                                    Text("10 sec").tag(10)
                                    Text("15 sec").tag(15)
                                    Text("30 sec").tag(30)
                                    Text("60 sec").tag(60)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // --- Section 3: Repetition ---
                    Section("Repetition") {
                        // Daily Reset Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Repeat Daily (Reset at Midnight)", isOn: $isRepeatDaily.animation())
                            Text("Task becomes due again each day at midnight.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        // Interval Input (Conditional)
                        if !isRepeatDaily {
                             Divider().padding(.vertical, 4) // Add separator
                             VStack(alignment: .leading, spacing: 8) {
                                Text("Repeat After Interval")
                                    .formLabelStyle()
                                Text("Task becomes due after this interval passes from completion.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    TextField("Interval", text: $repetitionInterval)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(minWidth: 50, idealWidth: 80)
                                    
                                    Picker("Unit", selection: $selectedRepetitionUnit) {
                                        ForEach(RepetitionUnit.allCases) { unit in
                                            Text(unit.rawValue).tag(unit)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 4)
                            // Add transition for smoother appearance/disappearance
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                    }
                    
                    // --- Section 4: Import (Add Mode Only) ---
                    if existingTask == nil {
                        Section("Import") {
                            Button(action: importFromClipboard) {
                                HStack {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Paste Task Data from Clipboard")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            Text("Supports JSON (single/array) or Google Sheets format.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .gesture(DragGesture().onChanged{_ in hideKeyboard() }) // Dismiss keyboard on scroll
                .environment(\.editMode, .constant(isChecklistTask && !checklistItems.isEmpty ? .active : .inactive))
            }
             .navigationBarTitle(existingTask == nil ? "Add New Task" : "Edit Task", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save", action: saveTask) // Use action parameter
            )
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Invalid Input"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                print("[AddTaskView \(viewId)] appeared - Checklist items count: \(checklistItems.count)")
                for (i, item) in checklistItems.enumerated() {
                    print("  Item \(i): \(item.title)")
                }
            }
        .fullScreenCover(isPresented: $showJSONPreview) {
                NavigationView {
                    ScrollView {
                        VStack(alignment: .leading) {
                            let tasks = (try? JSONSerialization.jsonObject(with: jsonPreviewContent.data(using: .utf8) ?? Data()) as? [[String: Any]]) ?? []
                            Text("Successfully parsed \(tasks.count) tasks")
                                .font(.headline)
                                .padding()

                            Text(formatJSON(jsonPreviewContent))
                                .font(.system(.body, design: .monospaced))
                                .padding()
                        }
                    }
                    .navigationTitle("JSON Preview")
                    .navigationBarItems(
                        leading: Button("Close") {
                            showJSONPreview = false
                        },
                        trailing: Button("Import Tasks") {
                            parseAndCreateTasksFromJSON(jsonPreviewContent)
                            showJSONPreview = false
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    // Add a helper view modifier for consistent label styling
    struct FormLabel: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func essentialityColor(_ essentiality: Essentiality) -> Color {
        switch essentiality {
        case .essential:
            return .red
        case .core:
            return .orange
        case .nonEssential:
            return .green
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func addChecklistItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let new = ChecklistItem(id: UUID(), title: trimmed, isCompleted: false, order: checklistItems.count)
        checklistItems.append(new)
        newItemText = ""
    }
    
    private func renumberChecklistItems() {
        for idx in checklistItems.indices {
            checklistItems[idx].order = idx
        }
    }

    private func moveChecklistItem(from source: IndexSet, to destination: Int) {
        checklistItems.move(fromOffsets: source, toOffset: destination)
        renumberChecklistItems()
    }

    // MARK: - Import Logic
    
    private func formatJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return jsonString
        }
        return prettyString
    }
    
    private func importFromClipboard() {
        let pasteboard = UIPasteboard.general
        var importCount = 0
        
        print("Starting clipboard import...")
        
        // First try JSON from plain text
        if let clipboardString = pasteboard.string {
            print("Found clipboard string: \(clipboardString)")
            do {
                // Try to parse as JSON first
                if let jsonData = clipboardString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) {
                    // Check if it's a single task or an array of tasks
                    let decoder = JSONDecoder()
                    if clipboardString.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                        let tasks = try decoder.decode([TaskInput].self, from: jsonData)
                        tasks.forEach { taskInput in
                            if createTaskFromInput(taskInput) {
                                importCount += 1
                            }
                        }
                    } else {
                        let task = try decoder.decode(TaskInput.self, from: jsonData)
                        if createTaskFromInput(task) {
                            importCount += 1
                        }
                    }
                    
                    // Show success alert and dismiss
                    alertMessage = "Successfully imported \(importCount) task\(importCount == 1 ? "" : "s")"
                    showAlert = true
                    if importCount > 0 {
                        // Don't dismiss here, let user see alert
                        // presentationMode.wrappedValue.dismiss()
                    }
                    return
                }
            } catch {
                alertMessage = "Failed to parse JSON: \(error.localizedDescription)"
                showAlert = true
                return
            }
        }
        
        // If we get here, try Google Sheets import
        if let items = pasteboard.items.first,
           let htmlString = items[UTType.html.identifier] as? String {
            do {
                let document: Document = try SwiftSoup.parse(htmlString)
                if try !document.select("google-sheets-html-origin").isEmpty() {
                    guard let table = try document.select("table").first() else {
                        throw NSError(domain: "ParseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No table found in HTML."])
                    }
                    
                    let headers = try table.select("tr").first()?.select("td, th").array().map {
                        try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    } ?? []
                    
                    let dataRows = try table.select("tr").array().dropFirst()
                    
                    for row in dataRows {
                        let cells = try row.select("td").array()
                        let cellData = try cells.map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                        
                        // Helper function to get value from headers
                        func getValue(_ key: String) -> String {
                            if let index = headers.firstIndex(of: key),
                               index < cellData.count {
                                return cellData[index]
                            }
                            return ""
                        }
                        
                        let task = TaskInput(
                            taskName: getValue("taskName"),
                            essentiality: Int(getValue("essentiality")) ?? nil,
                            minDuration: Int(getValue("minDuration")) ?? 0,
                            maxDuration: Int(getValue("maxDuration")) ?? 0,
                            repetitionInterval: Int(getValue("repetitionInterval")) ?? nil,
                            isSessionTask: getValue("isSessionTask") == "true" ? true : nil,
                            shouldTrackAverageTime: getValue("shouldTrackAverageTime") == "true" ? true : (getValue("shouldTrackAverageTime") == "false" ? false : nil),
                            isChecklistTask: getValue("isChecklistTask") == "true" ? true : nil,
                            checklistItems: nil, // CSV import doesn't support checklist items
                            uuid: getValue("uuid"),
                            lastCompleted: getValue("lastCompleted"),
                            order: Int(getValue("order")) ?? nil,
                            prepTime: Int(getValue("prepTime")) ?? nil
                        )
                        
                        if createTaskFromInput(task) {
                            importCount += 1
                        }
                    }
                    
                    // Show success alert and dismiss
                    alertMessage = "Successfully imported \(importCount) task\(importCount == 1 ? "" : "s")"
                    showAlert = true
                    if importCount > 0 {
                        // presentationMode.wrappedValue.dismiss()
                    }
                    return
                }
            } catch {
                alertMessage = "Error parsing HTML: \(error.localizedDescription)"
                showAlert = true
            }
        }
        
        alertMessage = "No valid JSON or Google Sheets data found in clipboard"
        showAlert = true
    }

    private func createTaskFromInput(_ input: TaskInput) -> Bool {
        // Use the imported UUID if available and valid, otherwise generate a new one
        let taskUUID: String
        if let importedUUID = input.uuid, !importedUUID.isEmpty, UUID(uuidString: importedUUID) != nil {
            taskUUID = importedUUID
            print("Using imported UUID for task '\(input.taskName)': \(taskUUID)")
        } else {
            taskUUID = UUID().uuidString
            print("Generated new UUID for task '\(input.taskName)': \(taskUUID)")
        }
        
        let task = CustomTask(
            uuid: taskUUID,
            taskName: input.taskName,
            essentiality: input.essentiality,
            minDuration: input.minDuration,
            maxDuration: input.maxDuration,
            lastCompleted: input.lastCompleted,
            repetitionInterval: input.repetitionInterval,
            order: input.order,
            isSessionTask: input.isSessionTask ?? false,
            shouldTrackAverageTime: input.shouldTrackAverageTime ?? true,
            isChecklistTask: input.isChecklistTask ?? false,
            checklistItems: input.checklistItems,
            prepTime: input.prepTime ?? 0
        )
        
        // Validate required fields
        guard !task.taskName.isEmpty,
              task.minDuration > 0,
              task.maxDuration >= task.minDuration else {
            print("Validation failed for imported task: \(input.taskName)")
            return false
        }
        
        onSave(task)
        return true
    }
    
    private func parseAndCreateTasksFromJSON(_ jsonString: String) {
        guard !jsonString.isEmpty else { return }
        
        // Try to decode either a single task or an array of tasks
        let decoder = JSONDecoder()
        
        do {
            if let jsonData = jsonString.data(using: .utf8) {
                let taskInputs: [TaskInput]
                
                // Try parsing as array first, fall back to single object if needed
                if jsonString.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                    taskInputs = try decoder.decode([TaskInput].self, from: jsonData)
                } else {
                    let singleTask = try decoder.decode(TaskInput.self, from: jsonData)
                    taskInputs = [singleTask]
                }
                
                // Process each task input
                for input in taskInputs {
                    if !createTaskFromInput(input) { // Use the helper function
                        print("Skipped invalid task during JSON import: \(input.taskName)")
                    }
                }
                
                // Dismiss the view after importing (consider showing alert first)
                 alertMessage = "Import finished. Check tasks list."
                 showAlert = true
                 // presentationMode.wrappedValue.dismiss() // Maybe dismiss after alert?
            }
        } catch {
            alertMessage = "Invalid JSON format or missing required fields: \(error.localizedDescription)"
            showAlert = true
        }
    }

    // MARK: - Save Action
    private func saveTask() {
        // --- Validation ---
        guard !taskName.isEmpty else {
            alertMessage = "Task name cannot be empty."
            showAlert = true
            return
        }
        
        let finalMinDuration: Int
        let finalMaxDuration: Int
        
        // In No Timers mode, use default duration if fields are empty
        if settingsManager.noTimersMode {
            if isVariableDuration {
                let min = Int(minDuration) ?? 10
                let max = Int(maxDuration) ?? 10
                finalMinDuration = min
                finalMaxDuration = max
            } else {
                let fixed = Int(duration) ?? 10
                finalMinDuration = fixed
                finalMaxDuration = fixed
            }
        } else {
            // Normal validation when timers are enabled
            if isVariableDuration {
                guard let min = Int(minDuration), let max = Int(maxDuration), min > 0, max > 0 else {
                    alertMessage = "Minimum and maximum duration must be positive numbers."
                    showAlert = true
                    return
                }
                guard min <= max else {
                    alertMessage = "Minimum duration cannot be greater than maximum duration."
                    showAlert = true
                    return
                }
                finalMinDuration = min
                finalMaxDuration = max
            } else {
                guard let fixed = Int(duration), fixed > 0 else {
                    alertMessage = "Duration must be a positive number."
                    showAlert = true
                    return
                }
                finalMinDuration = fixed
                finalMaxDuration = fixed
            }
        }
        
        // --- Calculate Repetition Interval ---
        let finalRepetitionInterval: Int?
        if isRepeatDaily {
            finalRepetitionInterval = 0 // Special value for daily reset
        } else if let intervalValue = Int(repetitionInterval), intervalValue > 0 {
            finalRepetitionInterval = selectedRepetitionUnit.toSeconds(value: intervalValue)
            if finalRepetitionInterval == nil {
                 alertMessage = "Invalid repetition interval specified."
                 showAlert = true
                 return
            }
        } else {
            finalRepetitionInterval = nil // No repetition
        }
        
        // --- Create/Update Task Object ---
        let finalChecklistItems = isChecklistTask ? checklistItems : []
        let taskToSave = CustomTask(
            uuid: uuid, // Use the existing UUID or the newly generated one
            taskName: taskName,
            essentiality: selectedEssentiality.value,
            minDuration: finalMinDuration,
            maxDuration: finalMaxDuration,
            lastCompleted: existingTask?.lastCompleted, // Preserve existing completion date on edit
            repetitionInterval: finalRepetitionInterval,
            order: existingTask?.order, // Preserve existing order on edit
            isSessionTask: isSessionTask,
            shouldTrackAverageTime: shouldTrackAverageTime,
            isChecklistTask: isChecklistTask,
            checklistItems: finalChecklistItems,
            prepTime: selectedPrepTime
        )
        
        // --- Call the onSave closure ---
        print("[AddTaskView \(viewId)] Saving task '\(taskName)' with \(finalChecklistItems.count) checklist items")
        for (index, item) in finalChecklistItems.enumerated() {
            print("  Item \(index): \(item.title) (id: \(item.id))")
        }
        onSave(taskToSave)
        
        // --- Dismiss only if adding a NEW task ---
        if existingTask == nil { // Check if we are in add mode
            presentationMode.wrappedValue.dismiss()
        } else {
            // For edit mode, force dismiss the sheet
            presentationMode.wrappedValue.dismiss()
        }
        // If existingTask is not nil, we are editing via a sheet,
        // and the sheet dismissal is handled automatically by SwiftUI.
    }
    
    // MARK: - Preview
    struct AddTaskView_Previews: PreviewProvider {
        static var previews: some View {
            // Preview for adding a new task
            AddTaskView { task in print("Preview saved new task: \(task.taskName)") }
            
            // Preview for editing an existing task
            AddTaskView(task: CustomTask(taskName: "Existing Task", minDuration: 15, maxDuration: 25, repetitionInterval: 86400 * 3, isSessionTask: true)) { task in
                 print("Preview saved edited task: \(task.taskName)") 
            }
        }
    }
}

private struct Collapsible: ViewModifier {
    let visible: Bool
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .frame(height: visible ? nil : 0)   // collapse without removal
            .clipped()
            .disabled(!visible)
    }
}

private extension View {
    func collapsible(visible: Bool) -> some View {
        modifier(Collapsible(visible: visible))
    }
}

// MARK: - View Extensions
extension View {
    func formLabelStyle() -> some View {
        self.modifier(AddTaskView.FormLabel())
    }
}
