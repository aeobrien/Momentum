import Foundation

/// TaskStorageInterface defines the required interface for TaskStorage
protocol TaskStorageInterface {
    func createTask(_ task: CustomTask) -> Result<CustomTask, Error>
    func fetchTasks() -> Result<[CustomTask], Error>
    func updateTask(_ task: CustomTask) -> Result<CustomTask, Error>
    func deleteTask(uuid: String) -> Result<Void, Error>
    
    /// Fetches a single task by UUID.
   ///
   /// - Parameter uuid: The UUID of the task.
   /// - Returns: The `CustomTask` if found, else `nil`.
    func fetchTask(by uuid: String) -> CustomTask?
}
