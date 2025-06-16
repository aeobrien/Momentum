import SwiftUI
import CoreData

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
            ScrollView {
                VStack(spacing: 12) {
                    // Routine Name Input
                    TextField("Routine Name", text: $routineName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    // Selected Tasks Section
                    VStack(alignment: .leading) {
                        Text("Routine Tasks")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                        
                        if selectedTasks.isEmpty {
                            Text("Add tasks from below to create your routine")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(selectedTasks, id: \.uuid) { cdTask in
                                TaskCard(
                                    cdTask: cdTask,
                                    isSelected: true,
                                    onRemove: {
                                        withAnimation {
                                            selectedTaskUUIDs.removeAll { $0 == cdTask.uuid?.uuidString }
                                        }
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Available Tasks Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Tasks")
                            .font(.headline)
                            .padding(.horizontal)
                        
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
                        .padding(.horizontal)
                        
                        if availableTasks.isEmpty {
                            Text(searchText.isEmpty ? "No available tasks found" : "No tasks match your search")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(availableTasks, id: \.uuid) { cdTask in
                                TaskCard(
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
                    .padding(.vertical)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
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
