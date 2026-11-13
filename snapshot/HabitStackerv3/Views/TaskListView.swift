import SwiftUI
import CoreData

struct TaskListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var viewModel: TaskViewModel

    // Replace the filtered tasks logic with a FetchRequest
    @FetchRequest private var cdTasks: FetchedResults<CDTask>
    @FetchRequest private var cdRoutines: FetchedResults<CDRoutine>

    @State private var searchText: String = ""
    @State private var showAddTask = false
    @State private var showTemplateOnboarding = false
    @State private var showCleanup = false
    @State private var sortMode: SortMode = .nameAsc
    @State private var infoMode = false
    @State private var showDeleteConfirmation = false
    @State private var taskToDelete: CDTask? = nil

    // Filter state
    @State private var routineFilter: CDRoutine? = nil

    private let logger = AppLogger.create(subsystem: "com.app.TaskListView", category: "UI")

    private var isFilterActive: Bool {
        routineFilter != nil
    }
    
    private var filteredAndSortedTasks: [CDTask] {
        let filtered = cdTasks.filter { cdTask in
            // Search filter
            let matchesSearch = searchText.isEmpty || (cdTask.taskName ?? "").localizedCaseInsensitiveContains(searchText)

            // Routine filter
            let matchesRoutine: Bool
            if let routine = routineFilter {
                let routineTaskUUIDs = (routine.taskRelations as? Set<CDRoutineTask>)?
                    .compactMap { $0.task?.uuid } ?? []
                matchesRoutine = cdTask.uuid != nil && routineTaskUUIDs.contains(cdTask.uuid!)
            } else {
                matchesRoutine = true
            }

            return matchesSearch && matchesRoutine
        }

        return filtered.sorted { task1, task2 in
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
    
    init(viewModel: TaskViewModel) {
        self.viewModel = viewModel

        // Task fetch request
        let taskRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        taskRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        _cdTasks = FetchRequest(fetchRequest: taskRequest, animation: .default)

        // Routine fetch request for filter menu
        let routineRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        routineRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDRoutine.name, ascending: true)]
        _cdRoutines = FetchRequest(fetchRequest: routineRequest, animation: .default)
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            // Search and Sort Section
            VStack(spacing: 12) {
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

                    Menu {
                        ForEach(cdRoutines, id: \.objectID) { routine in
                            Button(action: {
                                routineFilter = routine
                            }) {
                                HStack {
                                    Text(routine.name ?? "Unnamed")
                                    if routineFilter == routine {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        // Clear filter
                        if isFilterActive {
                            Divider()
                            Button(role: .destructive, action: {
                                routineFilter = nil
                            }) {
                                Label("Clear Filter", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(isFilterActive ? .orange : .blue)
                            .imageScale(.large)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.bottom, 12)
            .background(Color(.systemBackground))
            
            Divider()
            
            // Tasks List
            if filteredAndSortedTasks.isEmpty {
                VStack(spacing: 16) {
                    if isFilterActive || !searchText.isEmpty {
                        Text("No matching tasks")
                            .font(.headline)
                            .fontWeight(.bold)

                        Text("Try adjusting your search or filters")
                            .foregroundColor(.secondary)

                        if isFilterActive {
                            Button(action: {
                                routineFilter = nil
                            }) {
                                Label("Clear Filter", systemImage: "xmark.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                    } else {
                        Text("No tasks yet!")
                            .font(.headline)
                            .fontWeight(.bold)

                        VStack(spacing: 4) {
                            Text("Tap the + button in the top right to add your first task, or")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button(action: {
                                showTemplateOnboarding = true
                            }) {
                                Text("get started quicker by creating a routine from a template.")
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredAndSortedTasks, id: \.objectID) { cdTask in
                        NavigationLink(
                            destination: TaskDetailView(cdTask: cdTask)
                        ) {
                            TaskCard(cdTask: cdTask, isSelected: false)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                taskToDelete = cdTask
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        }
        .infoOverlay(
            showInfo: $infoMode,
            title: "Tasks",
            description: "View and manage all your tasks. Each task shows its duration and priority. Tap a task to edit it, or use the + button to create a new one."
        )
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
            leading: InfoButton(showInfo: $infoMode),
            trailing: HStack(spacing: 16) {
                Button(action: {
                    logger.debug("Opening cleanup view")
                    showCleanup = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.orange)
                }
                Button(action: {
                    logger.debug("Opening add task view")
                    showAddTask = true
                }) {
                    Image(systemName: "plus")
                }
            }
        )
        .fullScreenCover(isPresented: $showAddTask) {
            AddTaskView { newTask in
                createTask(from: newTask)
            }
        }
        .sheet(isPresented: $showTemplateOnboarding) {
            RoutineTemplateOnboardingView()
        }
        .sheet(isPresented: $showCleanup) {
            TaskCleanupView()
        }
        .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                taskToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let task = taskToDelete {
                    deleteTask(task)
                }
                taskToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(taskToDelete?.taskName ?? "this task")\"? This action cannot be undone.")
        }
    }
    
    
    private func deleteTask(_ cdTask: CDTask) {
        logger.info("Deleting task: \(cdTask.taskName ?? "")")
        
        // First remove all routine relationships
        if let relations = cdTask.routineRelations?.allObjects as? [CDRoutineTask] {
            for relation in relations {
                viewContext.delete(relation)
            }
        }
        
        viewContext.delete(cdTask)
        
        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to delete task", error: error)
        }
    }
    
    
    private func createTask(from task: CustomTask) {
        let cdTask = CDTask(context: viewContext)
        cdTask.updateCDTask(from: task)
        
        do {
            try viewContext.save()
            logger.info("Successfully created new task: \(task.taskName)")
        } catch {
            logger.error("Failed to create task", error: error)
        }
    }
}
