import Foundation

/// TaskStorageError defines various error types for TaskStorage operations
enum TaskStorageError: Error, LocalizedError {
    case invalidData
    case storageFailure
    case versionMismatch
    case taskNotFound
    case validationError
    case invalidUUID
    
    var errorDescription: String? {
        switch self {
            case .invalidData:
                return "Invalid data provided."
            case .storageFailure:
                return "Failed to access storage."
            case .versionMismatch:
                return "Version mismatch detected."
            case .taskNotFound:
                return "Task not found."
            case .validationError:
                return "Validation failed for the task."
            case .invalidUUID:
                return "The provided UUID string was invalid."
        }
    }
}
