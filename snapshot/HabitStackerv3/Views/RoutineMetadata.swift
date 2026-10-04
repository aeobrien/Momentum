import Foundation

/// Contains metadata for a routine, such as usage statistics.
///
/// - Important: Metadata should be updated appropriately during routine usage.

struct RoutineMetadata: Codable, Hashable, Equatable {
    var lastUsed: Date
    var totalCompletions: Int
    var averageCompletionTime: TimeInterval
}

