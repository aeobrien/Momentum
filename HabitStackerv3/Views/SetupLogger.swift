//
//  SetupLogger.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 23/10/2024.
//

import Foundation

/// Logger for the Setup System
struct SetupLogger {
    private static let subsystem = "com.yourapp.SetupSystem"
    private let logger: AppLogger
    
    /// Initializes the SetupLogger with a specific category
    ///
    /// - Parameter category: The category for logging
    init(category: String) {
        self.logger = AppLogger(subsystem: SetupLogger.subsystem, category: category)
    }
    
    /// Logger for setup configuration
    static func setupConfiguration() -> SetupLogger {
        return SetupLogger(category: "SetupConfiguration")
    }
    
    /// Logger for time management
    static func timeManagement() -> SetupLogger {
        return SetupLogger(category: "TimeManagement")
    }
    
    /// Generic logging method
    ///
    /// - Parameters:
    ///   - level: The log level
    ///   - message: The log message
    ///   - error: Optional error
    func log(_ level: LogLevel, _ message: String, error: Error? = nil) {
        logger.log(level, message, error: error)
    }
    
    func debug(_ message: String, error: Error? = nil) {
        logger.debug(message, error: error)
    }
    
    func info(_ message: String, error: Error? = nil) {
        logger.info(message, error: error)
    }
    
    func warning(_ message: String, error: Error? = nil) {
        logger.warning(message, error: error)
    }
    
    func error(_ message: String, error: Error? = nil) {
        logger.error(message, error: error)
    }
    
    func fatal(_ message: String, error: Error? = nil) {
        logger.fatal(message, error: error)
    }
}
