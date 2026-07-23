// Logging+Extensions.swift
import Foundation
import os

enum LogLevel: String, Codable, CaseIterable {
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case fatal = "Fatal"
}

/// Provides a unified logging interface for the application, primarily using os.Logger.
struct AppLogger {
    private let logger: Logger
    private let category: String
    private let logsInternally: Bool // Flag to control internal logging
    
    init(subsystem: String, category: String, logsInternally: Bool = true) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.category = category
        self.logsInternally = logsInternally
    }
    
    /// Logs a message to the system logger (os.Logger) with a specified log level.
    /// This method does NOT log to the InternalLogManager.
    func log(_ level: LogLevel, _ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(function)"
        var entry = "\(context) - \(message)"
        
        if let error = error {
            entry += " | Error: \(error.localizedDescription)"
        }
        
        // Log ONLY to system logger (os.Logger)
        switch level {
        case .debug:
            logger.debug("\(entry)")
        case .info:
            logger.info("\(entry)")
        case .warning:
            logger.warning("\(entry)")
        case .error:
            logger.error("\(entry)")
        case .fatal:
            logger.fault("\(entry)")
        }
        
        // Conditionally log to internal system, based on the flag
        if logsInternally {
            InternalLogManager.shared.log(level, message, context: context, error: error)
        }
    }
    
    // Convenience methods now only log to os.Logger via the updated log method
    func debug(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, error: error, file: file, function: function, line: line)
    }
    
    func info(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, error: error, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, error: error, file: file, function: function, line: line)
    }
    
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, error: error, file: file, function: function, line: line)
    }
    
    func fatal(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(.fatal, message, error: error, file: file, function: function, line: line)
    }
}

// MARK: - Logger Factory
extension AppLogger {
    /// Creates a logger instance for a specific subsystem and category
    static func create(subsystem: String, category: String) -> AppLogger {
        AppLogger(subsystem: subsystem, category: category, logsInternally: true)
    }
}
