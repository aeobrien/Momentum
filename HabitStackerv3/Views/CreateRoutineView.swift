import SwiftUI
import CoreData

// Custom compact task card for CreateRoutineView
struct CompactTaskCard: View {
    @ObservedObject var cdTask: CDTask
    let isSelected: Bool
    var onRemove: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    
    private func essentialityColor(_ value: Int16) -> Color {
        switch value {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .gray
        }
    }
    
    private var durationText: String {
        if cdTask.minDuration == cdTask.maxDuration {
            return "\(cdTask.minDuration)m"
        } else {
            return "\(cdTask.minDuration)-\(cdTask.maxDuration)m"
        }
    }
    
    private var essentialityText: String {
        switch cdTask.essentiality {
        case 3: return "Essential"
        case 2: return "Core"
        case 1: return "Optional"
        default: return "Optional"
        }
    }
    
    var body: some View {
        HStack {
            if isSelected {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .imageScale(.large)
                }
                .padding(.trailing, 4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cdTask.taskName ?? "")
                    .font(.headline)
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.gray)
                    Text(durationText)
                        .foregroundColor(.gray)
                }
                .font(.subheadline)
            }
            
            Spacer()
            
            Text(essentialityText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(essentialityColor(cdTask.essentiality).opacity(0.2))
                .foregroundColor(essentialityColor(cdTask.essentiality))
                .cornerRadius(8)
            
            if !isSelected {
                Button(action: { onAdd?() }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}

struct CreateRoutineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: RoutineViewModel
    
    @State private var routineName: String = ""
    @State private var selectedTaskUUIDs: [String] = []
    @State private var searchText: String = ""
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var sortMode: SortMode = .nameAsc
    @State private var editMode: EditMode = .inactive
    @State private var selectedTab = 0 // 0 for Available Tasks, 1 for Routine Tasks
    
    private let logger = AppLogger.create(subsystem: "com.app.CreateRoutineView", category: "UI")
    private let performanceMonitor = PerformanceMonitor.shared
    
    // Fetch available tasks
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)],
        animation: .default
    ) private var cdTasks: FetchedResults<CDTask>
    
    private var availableTasks: [CDTask] {
        return performanceMonitor.measureExecutionTime("filter_available_tasks") {
            cdTasks.filter { cdTask in
                guard let taskUUID = cdTask.uuid?.uuidString else { return false }
                return !selectedTaskUUIDs.contains(taskUUID) &&
                    (searchText.isEmpty || (cdTask.taskName ?? "").localizedCaseInsensitiveContains(searchText))
            }.sorted { task1, task2 in
                switch sortMode {
                case .nameAsc:
                    return (task1.taskName ?? "") < (task2.taskName ?? "")
                case .nameDesc:
                    return (task1.taskName ?? "") > (task2.taskName ?? "")
                case .essentialityDesc:
                    return task1.essentiality > task2.essentiality
                case .essentialityAsc:
                    return task1.essentiality < task2.essentiality
                case .timeDesc:
                    return task1.maxDuration > task2.maxDuration
                case .timeAsc:
                    return task1.maxDuration < task2.maxDuration
                }
            }
        }
    }
    
    private var selectedTasks: [CDTask] {
        selectedTaskUUIDs.compactMap { uuid in
            cdTasks.first { $0.uuid?.uuidString == uuid }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Routine Name Input
                TextField("Routine Name", text: $routineName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                // Tab Selection
                Picker("", selection: $selectedTab) {
                    Text("Available Tasks").tag(0)
                    Text("Routine Tasks").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Tab Content
                if selectedTab == 0 {
                    // Available Tasks Tab
                    VStack(spacing: 0) {
                        HStack {
                            SearchBar(text: $searchText)
                            
                            Menu {
                                ForEach(SortMode.allCases, id: \.self) { mode in
                                    Button(action: {
                                        sortMode = mode
                                        logger.debug("Sort mode changed to: \(mode.rawValue)")
                                    }) {
                                        HStack {
                                            Text(mode.rawValue)
                                            if sortMode == mode {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                                    .foregroundColor(.blue)
                                    .imageScale(.large)
                            }
                        }
                        .padding()
                        
                        ScrollView {
                            VStack(spacing: 8) {
                                if availableTasks.isEmpty {
                                    Text(searchText.isEmpty ? "No available tasks found" : "No tasks match your search")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                } else {
                                    ForEach(availableTasks, id: \.uuid) { cdTask in
                                        CompactTaskCard(
                                            cdTask: cdTask,
                                            isSelected: false,
                                            onAdd: {
                                                withAnimation {
                                                    if let uuid = cdTask.uuid?.uuidString {
                                                        selectedTaskUUIDs.append(uuid)
                                                    }
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                } else {
                    // Routine Tasks Tab
                    List {
                        if selectedTasks.isEmpty {
                            Text("No tasks added yet")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(selectedTasks, id: \.uuid) { cdTask in
                                CompactTaskCard(
                                    cdTask: cdTask,
                                    isSelected: true,
                                    onRemove: {
                                        withAnimation {
                                            selectedTaskUUIDs.removeAll { $0 == cdTask.uuid?.uuidString }
                                        }
                                    }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onMove { source, destination in
                                selectedTaskUUIDs.move(fromOffsets: source, toOffset: destination)
                            }
                            
                            // Small grey text underneath the tasks list
                            Text("Drag to re-order tasks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Create Routine")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveRoutine()
                }
                .disabled(routineName.trimmingCharacters(in: .whitespaces).isEmpty || selectedTaskUUIDs.isEmpty)
            )
            .alert(isPresented: $showErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func saveRoutine() {
        logger.info("Starting routine creation: \(routineName)")
        
        performanceMonitor.measureOperation("save_routine") {
            let cdRoutine = CDRoutine(context: viewContext)
            cdRoutine.uuid = UUID()
            cdRoutine.name = routineName
            cdRoutine.createdOn = Date()
            cdRoutine.lastUsed = Date()
            cdRoutine.totalCompletions = 0
            cdRoutine.averageCompletionTime = 0
            
            // Create task relations
            for (index, taskUUID) in selectedTaskUUIDs.enumerated() {
                guard let uuid = UUID(uuidString: taskUUID),
                      let cdTask = cdTasks.first(where: { $0.uuid == uuid }) else {
                    logger.warning("Failed to find task with UUID: \(taskUUID)")
                    continue
                }
                
                let relation = CDRoutineTask(context: viewContext)
                relation.order = Int32(index)
                relation.task = cdTask
                relation.routine = cdRoutine
                
                logger.debug("Added task to routine: \(cdTask.taskName ?? "")")
            }
            
            do {
                try viewContext.save()
                logger.info("Successfully created routine: \(routineName)")
                presentationMode.wrappedValue.dismiss()
            } catch {
                logger.error("Failed to save routine", error: error)
                errorMessage = "Failed to save routine: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}
