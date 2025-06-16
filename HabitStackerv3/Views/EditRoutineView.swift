import SwiftUI
import CoreData

struct EditRoutineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    // Fetch request for all tasks
    @FetchRequest private var cdTasks: FetchedResults<CDTask>
    
    let cdRoutine: CDRoutine
    @State private var routineName: String
    @State private var searchText: String = ""
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var sortMode: SortMode = .nameAsc
    @State private var editMode: EditMode = .active
    
    private let logger = AppLogger.create(subsystem: "com.app.EditRoutineView", category: "UI")
    
    private var sortedRelations: [CDRoutineTask] {
        (cdRoutine.taskRelations?.allObjects as? [CDRoutineTask] ?? [])
            .sorted { $0.order < $1.order }
    }
    
    private var selectedTaskUUIDs: Set<UUID> {
        Set(sortedRelations.compactMap { $0.task?.uuid })
    }
    
    private var availableTasks: [CDTask] {
        cdTasks.filter { cdTask in
            guard let taskUUID = cdTask.uuid else { return false }
            return !selectedTaskUUIDs.contains(taskUUID) &&
                   (searchText.isEmpty || (cdTask.taskName?.localizedCaseInsensitiveContains(searchText) ?? false))
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
    
    init(cdRoutine: CDRoutine) {
        self.cdRoutine = cdRoutine
        self._routineName = State(initialValue: cdRoutine.name ?? "")
        
        // Initialize fetch request for tasks
        let request: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        _cdTasks = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Routine Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Routine Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Enter routine name", text: $routineName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding()
            .background(Color(.systemBackground))
            
            List {
                Section(header:
                    HStack {
                        Text("ROUTINE TASKS")
                        Spacer()
                        Text("Drag to reorder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                ) {
                    if sortedRelations.isEmpty {
                        Text("Add tasks from below to create your routine")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color(.systemGroupedBackground))
                    } else {
                        ForEach(sortedRelations, id: \.self) { relation in
                            if let task = relation.task {
                                TaskCard(
                                    cdTask: task,
                                    isSelected: true,
                                    onRemove: {
                                        removeTask(relation)
                                    }
                                )
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            removeTask(relation)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .onMove(perform: moveTask)
                    }
                }
                
                Section(header:
                    VStack(spacing: 8) {
                        Text("AVAILABLE TASKS")
                        
                        HStack {
                            SearchBar(text: $searchText)
                            
                            Menu {
                                ForEach(SortMode.allCases, id: \.self) { mode in
                                    Button(action: { sortMode = mode }) {
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
                    }
                ) {
                    if availableTasks.isEmpty {
                        Text(searchText.isEmpty ? "No available tasks" : "No tasks match your search")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color(.systemGroupedBackground))
                    } else {
                        ForEach(availableTasks) { task in
                            TaskCard(
                                cdTask: task,
                                isSelected: false,
                                onAdd: {
                                    addTask(task)
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Edit Routine")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            },
            trailing: Button("Save") {
                saveRoutine()
            }
            .disabled(routineName.trimmingCharacters(in: .whitespaces).isEmpty)
        )
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private func moveTask(from source: IndexSet, to destination: Int) {
        var relations = sortedRelations
        relations.move(fromOffsets: source, toOffset: destination)
        
        // Update order for all relations
        for (index, relation) in relations.enumerated() {
            relation.order = Int32(index)
        }
        
        saveContext()
    }
    
    private func removeTask(_ relation: CDRoutineTask) {
        viewContext.delete(relation)
        saveContext()
    }
    
    private func addTask(_ task: CDTask) {
        let relation = CDRoutineTask(context: viewContext)
        relation.task = task
        relation.routine = cdRoutine
        relation.order = Int32(sortedRelations.count)
        saveContext()
    }
    
    private func saveRoutine() {
        cdRoutine.name = routineName.trimmingCharacters(in: .whitespaces)
        
        if saveContext() {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func saveContext() -> Bool {
        do {
            try viewContext.save()
            return true
        } catch {
            logger.error("Failed to save context", error: error)
            errorMessage = error.localizedDescription
            showErrorAlert = true
            return false
        }
    }
}
