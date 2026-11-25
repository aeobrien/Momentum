import Foundation

/// Defines errors that can occur within the Routine Management System.
enum RoutineError: Error, LocalizedError {
    case invalidTaskReference(uuid: String)
    case routineNotFound
    case orderValidationFailed
    case storageError(description: String)
    case priorityCalculationError(description: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidTaskReference(let uuid):
            return "Invalid task reference detected: \(uuid)"
        case .routineNotFound:
            return "Routine not found."
        case .orderValidationFailed:
            return "Order validation failed."
        case .storageError(let description):
            return "Storage error: \(description)"
        case .priorityCalculationError(let description):
            return "Priority calculation error: \(description)"
        }
    }
}
