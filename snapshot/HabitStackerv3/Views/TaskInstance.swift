import Foundation

/// TaskInstance represents a runtime instance of a task
///
/// Contains dynamic properties such as start time, expected end time, and completion status.
struct TaskInstance {
    /// Unique identifier for the instance
    let id: UUID
    
    /// Associated CustomTask
    var task: CustomTask
    
    /// Start time of the task
    var startTime: Date?
    
    /// Expected end time of the task
    var expectedEndTime: Date?
    
    /// Completion status of the task
    var isCompleted: Bool
    
    /// Initializes a new TaskInstance
    ///
    /// - Parameters:
    ///   - task: The associated CustomTask
    ///   - startTime: Start time
    ///   - expectedEndTime: Expected end time
    ///   - isCompleted: Completion status
    init(task: CustomTask,
         startTime: Date? = nil,
         expectedEndTime: Date? = nil,
         isCompleted: Bool = false) {
        self.id = UUID()
        self.task = task
        self.startTime = startTime
        self.expectedEndTime = expectedEndTime
        self.isCompleted = isCompleted
    }
}
