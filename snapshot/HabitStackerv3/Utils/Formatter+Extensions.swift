import Foundation

// Shared date formatter instance for consistent ISO8601 date parsing/formatting.
extension ISO8601DateFormatter {
    static let shared = ISO8601DateFormatter()
} 