import SwiftUI
import CoreData

struct TaskListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var viewModel: TaskViewModel
    
    // Replace the filtered tasks logic with a FetchRequest
    @FetchRequest private var cdTasks: FetchedResults<CDTask>
    @State private var searchText: String = ""
    @State private var showAddTask = false
    @State private var showTemplateOnboarding = false
    @State private var sortMode: SortMode = .nameAsc
    @State private var infoMode = false
    
    private let logger = AppLogger.create(subsystem: "com.app.TaskListView", category: "UI")
    
    private var filteredAndSortedTasks: [CDTask] {
        let filtered = cdTasks.filter { cdTask in
            searchText.isEmpty || (cdTask.taskName ?? "").localizedCaseInsensitiveContains(searchText)
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
        
        let request: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        
        // Removed predicate - TaskListView should show ALL tasks
        // request.predicate = NSPredicate(format: "isSessionTask == %@", NSNumber(value: false))
        
        // Set sort descriptors (existing code)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        
        _cdTasks = FetchRequest(fetchRequest: request, animation: .default)
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
                    Text("No tasks yet!")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    if searchText.isEmpty {
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
                    } else {
                        Text("Try adjusting your search")
                            .foregroundColor(.secondary)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTask(cdTask)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
            trailing: Button(action: {
                logger.debug("Opening add task view")
                showAddTask = true
            }) {
                Image(systemName: "plus")
            }
        )
        .sheet(isPresented: $showAddTask) {
            AddTaskView { newTask in
                createTask(from: newTask)
            }
        }
        .sheet(isPresented: $showTemplateOnboarding) {
            RoutineTemplateOnboardingView()
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
