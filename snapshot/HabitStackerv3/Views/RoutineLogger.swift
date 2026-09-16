// RoutineLogger.swift

import os

/// Provides logging capabilities for the Routine Management System.
///
/// RoutineLogger wraps AppLogger to provide specialized logging functionality
/// for the Routine Management System, ensuring consistent logging patterns
/// across the routine-related features of the application.
///
/// - Important: All logs are tagged with the Routine Management System subsystem
/// to distinguish them from other system logs.
struct RoutineLogger {
    /// The underlying logger instance
    private let logger: AppLogger
    
    /// The subsystem identifier for all routine management logs
    private static let subsystem = "com.yourapp.RoutineManagementSystem"
    
    /// Creates a new RoutineLogger instance for a specific category
    /// - Parameter category: The logging category, typically representing a specific
    ///   component or feature within the Routine Management System
    init(category: String) {
        self.logger = AppLogger.create(
            subsystem: RoutineLogger.subsystem,
            category: category
        )
    }
    
    /// Logs a debug message
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error to include in the log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func debug(_ message: String,
              error: Error? = nil,
              file: String = #file,
              function: String = #function,
              line: Int = #line) {
        logger.debug(message, error: error, file: file, function: function, line: line)
    }
    
    /// Logs an info message
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error to include in the log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func info(_ message: String,
             error: Error? = nil,
             file: String = #file,
             function: String = #function,
             line: Int = #line) {
        logger.info(message, error: error, file: file, function: function, line: line)
    }
    
    /// Logs a warning message
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error to include in the log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func warning(_ message: String,
                error: Error? = nil,
                file: String = #file,
                function: String = #function,
                line: Int = #line) {
        logger.warning(message, error: error, file: file, function: function, line: line)
    }
    
    /// Logs an error message
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error to include in the log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func error(_ message: String,
              error: Error? = nil,
              file: String = #file,
              function: String = #function,
              line: Int = #line) {
        logger.error(message, error: error, file: file, function: function, line: line)
    }
    
    /// Logs a fatal error message
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error to include in the log
    ///   - file: Source file name (automatically provided)
    ///   - function: Function name (automatically provided)
    ///   - line: Line number (automatically provided)
    func fatal(_ message: String,
              error: Error? = nil,
              file: String = #file,
              function: String = #function,
              line: Int = #line) {
        logger.fatal(message, error: error, file: file, function: function, line: line)
    }
}

// MARK: - Convenience Initializers
extension RoutineLogger {
    /// Creates a logger instance for the routine execution component
    static func routineExecution() -> RoutineLogger {
        RoutineLogger(category: "RoutineExecution")
    }
    
    /// Creates a logger instance for the routine scheduling component
    static func routineScheduling() -> RoutineLogger {
        RoutineLogger(category: "RoutineScheduling")
    }
    
    /// Creates a logger instance for the routine validation component
    static func routineValidation() -> RoutineLogger {
        RoutineLogger(category: "RoutineValidation")
    }
    
    /// Creates a logger instance for the routine analytics component
    static func routineAnalytics() -> RoutineLogger {
        RoutineLogger(category: "RoutineAnalytics")
    }
}

#if DEBUG
// MARK: - Testing Support
extension RoutineLogger {
    /// Creates a logger instance specifically for testing purposes
    /// - Parameter testName: The name of the test or test suite
    /// - Returns: A RoutineLogger configured for test logging
    static func testing(_ testName: String) -> RoutineLogger {
        RoutineLogger(category: "Testing-\(testName)")
    }
}
#endif
