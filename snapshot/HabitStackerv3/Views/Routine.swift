import Foundation

/// Represents a routine, which is an ordered collection of task UUIDs referencing tasks in the main Task Storage System.
///
/// - Important: Ensure all task UUIDs exist in TaskStorage before creating or updating a routine.
struct Routine: Identifiable, Codable, Hashable, Equatable {
    let id: String
    var name: String
    var createdOn: Date
    var taskUUIDs: [String] // Ordered list of task UUIDs
    var metadata: RoutineMetadata
}
