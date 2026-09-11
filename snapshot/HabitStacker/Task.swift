import Foundation

/// Represents a single task within a routine.
struct Task: Identifiable {
    /// Unique identifier for the task, useful for lists and iteration.
    let id = UUID()
    /// The display name of the task.
    let name: String
    /// The planned duration of the task in seconds.
    let duration: TimeInterval
} 