// PerformanceMonitor.swift

import Foundation
import os

/// PerformanceMonitor measures and logs performance metrics of operations
final class PerformanceMonitor {
    /// Logger instance for logging performance metrics
    private let logger: AppLogger
    
    /// Shared instance for global access
    static let shared = PerformanceMonitor()
    
    /// Private initializer to enforce singleton pattern
    private init() {
        self.logger = AppLogger.create(
            subsystem: "com.app.Performance",
            category: "Monitoring"
        )
    }
    
    /// Measures the performance of an operation
    /// - Parameters:
    ///   - name: Name of the operation
    ///   - operation: The operation closure to execute
    func measureOperation(_ name: String, operation: () throws -> Void) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()
        
        try operation()
        
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000 // ms
        let memoryDelta = getMemoryUsage() - startMemory
        
        logger.debug("""
            Performance Metrics:
            Operation: \(name)
            Duration: \(String(format: "%.2f", duration))ms
            Memory Delta: \(String(format: "%.2f", memoryDelta))MB
            """)
    }
    
    /// Retrieves current memory usage in MB
    /// - Returns: Memory usage in MB
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            logger.warning("Failed to get memory usage")
            return 0.0
        }
        
        return Double(info.resident_size) / (1024 * 1024) // Convert to MB
    }
    
    /// Measures and logs the execution time of a block
    /// - Parameters:
    ///   - name: Name of the operation being measured
    ///   - block: The block of code to measure
    /// - Returns: The result of the block execution
    func measureExecutionTime<T>(_ name: String, block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000 // ms
        
        logger.debug("""
            Execution Time:
            Operation: \(name)
            Duration: \(String(format: "%.2f", duration))ms
            """)
        
        return result
    }
}

// MARK: - Convenience Methods
extension PerformanceMonitor {
    /// Measures memory usage at a specific point
    /// - Parameter label: Label for the measurement point
    func measureMemoryUsage(label: String) {
        let usage = getMemoryUsage()
        logger.debug("""
            Memory Usage:
            Point: \(label)
            Usage: \(String(format: "%.2f", usage))MB
            """)
    }
}

#if DEBUG
// MARK: - Testing Support
extension PerformanceMonitor {
    /// Resets the performance monitor (for testing)
    func reset() {
        // Add any reset logic needed for testing
        logger.debug("Performance monitor reset")
    }
}
#endif
