import Foundation
import CoreData

/// ViewModel for managing tasks.
class TaskViewModel: ObservableObject {
    @Published var tasks: [CustomTask] = []
    @Published var selectedTask: CustomTask?
    @Published var errorMessage: String?
    
    // Reference to the Core Data storage
    private let taskStorage = TaskStorageCoreData.shared
    private let logger = AppLogger.create(subsystem: "com.app.TaskViewModel", category: "ViewModel")
    
    init() {
        fetchTasks()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDataStoreChange),
            name: .dataStoreDidChange,
            object: nil
        )
    }
    
    @objc private func handleDataStoreChange() {
        logger.info("Data store changed, refreshing tasks")
        // Clear selected task as it may not exist in the new store
        selectedTask = nil
        fetchTasks()
    }
    
    /// Fetches all tasks from storage.
    func fetchTasks() {
        let result = taskStorage.fetchTasks()
        switch result {
        case .success(let fetchedTasks):
            DispatchQueue.main.async {
                self.tasks = fetchedTasks
            }
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to fetch tasks", error: error)
        }
    }
    
    /// Creates a new task.
    ///
    /// - Parameters:
    ///   - taskName: Name of the task.
    ///   - essentiality: Essentiality level of the task.
    ///   - minDuration: Minimum duration in minutes.
    ///   - maxDuration: Maximum duration in minutes.
    ///   - repetitionInterval: Repetition interval in seconds.
    func createTask(taskName: String, essentiality: Int, minDuration: Int, maxDuration: Int, repetitionInterval: Int) {
        let newTask = CustomTask(
            uuid: UUID().uuidString,
            taskName: taskName,
            essentiality: essentiality,
            minDuration: minDuration,
            maxDuration: maxDuration,
            repetitionInterval: repetitionInterval
        )
        
        let result = taskStorage.createTask(newTask)
        switch result {
        case .success(let task):
            DispatchQueue.main.async {
                self.tasks.append(task)
            }
            logger.info("Successfully created task: \(taskName)")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to create task: \(taskName)", error: error)
        }
    }
    
    /// Deletes a task.
    ///
    /// - Parameter task: Task to delete.
    func deleteTask(_ task: CustomTask) {
        let result = taskStorage.deleteTask(uuid: task.uuid)
        switch result {
        case .success:
            DispatchQueue.main.async {
                self.tasks.removeAll { $0.uuid == task.uuid }
            }
            logger.info("Successfully deleted task: \(task.taskName)")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to delete task: \(task.taskName)", error: error)
        }
    }
    
    /// Updates an existing task.
    ///
    /// - Parameter task: The updated task.
    func updateTask(_ task: CustomTask) {
        let result = taskStorage.updateTask(task)
        switch result {
        case .success(let updatedTask):
            DispatchQueue.main.async {
                if let index = self.tasks.firstIndex(where: { $0.uuid == updatedTask.uuid }) {
                    self.tasks[index] = updatedTask
                }
            }
            logger.info("Successfully updated task: \(task.taskName)")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to update task: \(task.taskName)", error: error)
        }
    }
    
    /// Fetches a single task by UUID.
    ///
    /// - Parameter uuid: The UUID of the task.
    /// - Returns: The `CustomTask` if found, else `nil`.
    func fetchTask(by uuid: String) -> CustomTask? {
        return taskStorage.fetchTask(by: uuid)
    }
}
