// TaskStorage.swift

import Foundation
import CryptoKit
import OSLog

/// TaskStorage manages persistent storage and versioning of tasks
///
/// This class handles all CRUD operations for tasks, ensuring data integrity
/// and proper version control. It serves as the single source of truth for
/// task data in the application.
///
/// - Important: All operations are thread-safe and handle errors gracefully
/// - Warning: Must be initialized before any task operations
final class TaskStorage: TaskStorageInterface {
    
    /// Current version of the task storage
    /// - Note: Updated automatically on any schema changes
    private(set) var version: Version
    
    /// Singleton instance for global access
    static let shared = TaskStorage()
    
    /// File URL for the storage file
    private let fileURL: URL
    
    /// Serial queue for thread-safe operations
    private let queue = DispatchQueue(label: "com.app.TaskStorageQueue")
    
    /// Logger instance for logging (Explicitly using OSLog.Logger)
    private let logger = AppLogger.create(subsystem: "com.app.TaskStorage", category: "Storage")

    /// In-memory storage of tasks
    private(set) var tasks: [CustomTask] = []
    
    /// Private initializer to enforce singleton usage
    private init() {
        // Initialize file URL
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documents.appendingPathComponent("Tasks.json")
        
        // Initialize version
        self.version = Version(major: 1, minor: 0, patch: 0)
        
        // Load existing data
        do {
            try loadFromStorage()
        } catch {
            logger.log(.error, "Failed to load storage: \(error.localizedDescription)")
        }
    }
    
    // MARK: - TaskStorageInterface Methods
    
    /// Creates a new task in storage
    /// - Parameter task: The task to create
    /// - Returns: Result containing created task or error
    func createTask(_ task: CustomTask) -> Result<CustomTask, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: createTask")
                try measureOperation("createTask") {
                    // Validate task
                    try validateTask(task)
                    
                    // Add task
                    tasks.append(task)
                    
                    // Update version
                    incrementPatchVersion()
                    
                    // Save to storage
                    try saveToStorage()
                    
                    // Log completion
                    logger.log(.info, "Completed operation: createTask")
                }
                return .success(task)
            } catch {
                logger.log(.error, "Operation failed: createTask - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Fetches tasks from storage
    /// - Returns: Result containing array of tasks or error
    func fetchTasks() -> Result<[CustomTask], Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: fetchTasks")
                try measureOperation("fetchTasks") {
                    try loadFromStorage()
                }
                logger.log(.info, "Completed operation: fetchTasks")
                return .success(tasks)
            } catch {
                logger.log(.error, "Operation failed: fetchTasks - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Updates an existing task in storage
    /// - Parameter task: The updated task
    /// - Returns: Result containing updated task or error
    func updateTask(_ task: CustomTask) -> Result<CustomTask, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: updateTask")
                try measureOperation("updateTask") {
                    // Find index
                    guard let index = tasks.firstIndex(where: { $0.uuid == task.uuid }) else {
                        throw TaskStorageError.taskNotFound
                    }
                    
                    // Validate task
                    try validateTask(task)
                    
                    // Update task
                    tasks[index] = task
                    
                    // Update version
                    incrementPatchVersion()
                    
                    // Save to storage
                    try saveToStorage()
                }
                logger.log(.info, "Completed operation: updateTask")
                return .success(task)
            } catch {
                logger.log(.error, "Operation failed: updateTask - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Deletes a task from storage
    /// - Parameter uuid: UUID of the task to delete
    /// - Returns: Result containing Void or error
    func deleteTask(uuid: String) -> Result<Void, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: deleteTask")
                try measureOperation("deleteTask") {
                    // Find index
                    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else {
                        throw TaskStorageError.taskNotFound
                    }
                    
                    // Remove task
                    tasks.remove(at: index)
                    
                    // Update version
                    incrementPatchVersion()
                    
                    // Save to storage
                    try saveToStorage()
                }
                logger.log(.info, "Completed operation: deleteTask")
                return .success(())
            } catch {
                logger.log(.error, "Operation failed: deleteTask - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Fetches a single task by UUID.
    ///
    /// - Parameter uuid: The UUID of the task.
    /// - Returns: The `CustomTask` if found, else `nil`.
    func fetchTask(by uuid: String) -> CustomTask? {
        return tasks.first { $0.uuid == uuid }
    }
    
    // MARK: - Private Methods
    
    /// Validates a task's data
    /// - Parameter task: The task to validate
    /// - Throws: TaskStorageError.validationError if validation fails
    private func validateTask(_ task: CustomTask) throws {
        guard !task.taskName.isEmpty else {
            throw TaskStorageError.validationError
        }
        guard task.minDuration <= task.maxDuration else {
            throw TaskStorageError.invalidData
        }
        // Additional validations as needed
    }
    
    /// Loads tasks from storage
    /// - Throws: TaskStorageError.storageFailure if loading fails
    private func loadFromStorage() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(StorageData.self, from: data)
            self.version = decoded.version
            self.tasks = decoded.tasks
            logger.log(.debug, "Loaded tasks from storage")
        } else {
            // Initialize storage file
            try saveToStorage()
            logger.log(.debug, "Initialized new storage file")
        }
    }
    
    /// Saves tasks to storage
    /// - Throws: TaskStorageError.storageFailure if saving fails
    private func saveToStorage() throws {
        let data = StorageData(version: version, tasks: tasks)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: [.atomicWrite])
        logger.log(.debug, "Saved tasks to storage")
    }
    
    /// Increments the patch version
    private func incrementPatchVersion() {
        version = Version(major: version.major, minor: version.minor, patch: version.patch + 1)
        logger.log(.info, "Version update: \(version)")
    }
    
    /// Measures the performance of an operation
    /// - Parameters:
    ///   - name: Name of the operation
    ///   - operation: The operation closure to execute
    private func measureOperation(_ name: String, operation: () throws -> Void) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()
        
        try operation()
        
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000 // ms
        let memoryDelta = getMemoryUsage() - startMemory
        
        logger.log(.debug, """
            Operation: \(name)
            Duration: \(duration)ms
            Memory Delta: \(memoryDelta)MB
            """)
    }
    
    /// Retrieves current memory usage in MB
    /// - Returns: Memory usage in MB
    private func getMemoryUsage() -> Double {
        // Placeholder implementation
        // In a real scenario, use appropriate APIs to get memory usage
        return Double.random(in: 0...10)
    }
    
    // MARK: - Testing Methods
    
    #if DEBUG
    /// Resets the storage to its initial state. Intended for testing purposes only.
    func resetStorage() throws {
        queue.sync {
            self.tasks = []
            self.version = Version(major: 1, minor: 0, patch: 0)
        }
        try saveToStorage()
        logger.log(.debug, "Storage has been reset for testing")
    }
    #endif
}

/// StorageData represents the structure of the storage file
private struct StorageData: Codable {
    var version: Version
    var tasks: [CustomTask]
}
