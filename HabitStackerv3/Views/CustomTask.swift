import Foundation

/// CustomTask represents a task with various attributes for management
///
/// Conforms to Identifiable, Codable, and Equatable for easy identification, encoding/decoding, and comparison.
///
/// - Important: `uuid` is generated using CryptoKit to ensure secure and unique identifiers.
struct CustomTask: Identifiable, Codable, Equatable {
    /// Unique identifier for the task
    var id: String { uuid }
    
    /// Securely generated UUID for the task
    var uuid: String
    
    /// Name of the task
    var taskName: String
    
    /// Essentiality level of the task
    var essentiality: Int?
    
    /// Minimum duration in minutes
    var minDuration: Int
    
    /// Maximum duration in minutes
    var maxDuration: Int
    
    /// Last completion date in ISO8601 format
    var lastCompleted: String?
    
    /// Repetition interval in days
    var repetitionInterval: Int?
    
    /// Order for task sorting
    var order: Int?
    
    /// Indicates if the task is session-specific (only appears in routines)
    /// Defaults to false.
    var isSessionTask: Bool
    
    /// Flag indicating whether averaged time completions should be recorded for this task
    /// Defaults to true.
    var shouldTrackAverageTime: Bool
    
    /// Average completion time in seconds, calculated from stored completion times
    var averageCompletionTime: TimeInterval?
    
    /// Initializes a new CustomTask
    ///
    /// - Parameters:
    ///   - uuid: Unique identifier
    ///   - taskName: Name of the task
    ///   - essentiality: Essentiality level
    ///   - minDuration: Minimum duration
    ///   - maxDuration: Maximum duration
    ///   - lastCompleted: Last completed date
    ///   - repetitionInterval: Repetition interval
    ///   - order: Order for sorting
    ///   - isSessionTask: Indicates if the task is session-specific (defaults to false)
    ///   - shouldTrackAverageTime: Whether to track average completion times (defaults to true)
    ///   - averageCompletionTime: Average completion time in seconds
    init(uuid: String = UUID().uuidString,
         taskName: String,
         essentiality: Int? = nil,
         minDuration: Int,
         maxDuration: Int,
         lastCompleted: String? = nil,
         repetitionInterval: Int? = nil,
         order: Int? = nil,
         isSessionTask: Bool = false,
         shouldTrackAverageTime: Bool = true,
         averageCompletionTime: TimeInterval? = nil) {
        self.uuid = uuid
        self.taskName = taskName
        self.essentiality = essentiality
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.lastCompleted = lastCompleted
        self.repetitionInterval = repetitionInterval
        self.order = order
        self.isSessionTask = isSessionTask
        self.shouldTrackAverageTime = shouldTrackAverageTime
        self.averageCompletionTime = averageCompletionTime
    }
}
