//
//  LogRecord.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 27/10/2024.
//
// LogRecord.swift
import Foundation

struct LogRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let context: String
    let error: String?
    
    init(level: LogLevel, message: String, context: String, error: Error? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.context = context
        self.error = error?.localizedDescription
    }
    
    // Custom Codable implementation
    enum CodingKeys: String, CodingKey {
        case id, timestamp, level, message, context, error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LogLevel.self, forKey: .level)
        message = try container.decode(String.self, forKey: .message)
        context = try container.decode(String.self, forKey: .context)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(message, forKey: .message)
        try container.encode(context, forKey: .context)
        try container.encodeIfPresent(error, forKey: .error)
    }

    // MARK: - Computed Properties

    /// Formats the log record into a human-readable string.
    var formattedString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestampString = dateFormatter.string(from: timestamp)

        var output = "[\(timestampString)] [\(level.rawValue.uppercased())] \(context) - \(message)"
        if let error = error {
            output += " | Error: \(error)"
        }
        return output
    }
}
