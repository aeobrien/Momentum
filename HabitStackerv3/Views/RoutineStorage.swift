// RoutineStorage.swift
import Foundation
import OSLog

/// Manages collections of ordered task references.
///
/// This class handles the creation and management of routines, which are ordered
/// collections of task UUIDs that reference tasks in the main task storage.
/// It maintains the integrity of these references and handles reordering operations.
///
/// - Important: Requires initialized TaskStorage instance.
/// - Warning: Must validate task existence before creating references.
final class RoutineStorage: RoutineStorageInterface {
    
    /// Current version of the routine storage
    private(set) var version: Version
    
    /// Singleton instance for global access
    static let shared = RoutineStorage()
    
    /// File URL for the storage file
    private let fileURL: URL
    
    /// Serial queue for thread-safe operations
    private let queue = DispatchQueue(label: "com.app.RoutineStorageQueue")
    
    /// Logger instance for logging
    fileprivate let logger = AppLogger.create(subsystem: "com.app.RoutineStorage", category: "Storage")
    
    /// In-memory storage of routines
    private(set) var routines: [Routine] = []
    
    /// Key for storing active routine ID in UserDefaults
    private let activeRoutineKey = "activeRoutineID"
    
    /// Private initializer to enforce singleton usage
    private init() {
        // Initialize file URL
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documents.appendingPathComponent("Routines.json")
        
        // Initialize version
        self.version = Version(major: 1, minor: 0, patch: 0)
        
        // Load existing data
        do {
            try loadFromStorage()
        } catch {
            logger.log(.error, "Failed to load storage: \(error.localizedDescription)")
        }
    }
    
    // MARK: - RoutineStorageInterface Methods
    
    /// Creates a new routine in storage
    func createRoutine(_ routine: Routine) -> Result<Routine, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: createRoutine")
                try measureOperation("createRoutine") {
                    try validateRoutine(routine)
                    routines.append(routine)
                    incrementPatchVersion()
                    try saveToStorage()
                    logger.log(.info, "Completed operation: createRoutine")
                }
                return .success(routine)
            } catch {
                logger.log(.error, "Operation failed: createRoutine - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Fetches all routines
    func fetchRoutines() -> Result<[Routine], Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: fetchRoutines")
                try measureOperation("fetchRoutines") {
                    try loadFromStorage()
                }
                logger.log(.info, "Completed operation: fetchRoutines")
                return .success(routines)
            } catch {
                logger.log(.error, "Operation failed: fetchRoutines - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Fetches a specific routine by ID
    func fetchRoutine(by id: String) -> Routine? {
        return routines.first { $0.id == id }
    }
    
    /// Updates an existing routine in storage
    func updateRoutine(_ routine: Routine) -> Result<Routine, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: updateRoutine")
                try measureOperation("updateRoutine") {
                    // Find index
                    guard let index = routines.firstIndex(where: { $0.id == routine.id }) else {
                        throw RoutineStorageError.routineNotFound
                    }
                    
                    // Validate routine
                    try validateRoutine(routine)
                    
                    // Update routine
                    routines[index] = routine
                    
                    // Update version
                    incrementPatchVersion()
                    
                    // Save to storage
                    try saveToStorage()
                    
                    // Log completion
                    logger.log(.info, "Completed operation: updateRoutine")
                }
                return .success(routine)
            } catch {
                logger.log(.error, "Operation failed: updateRoutine - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Deletes a routine from storage
    func deleteRoutine(id: String) -> Result<Void, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: deleteRoutine")
                try measureOperation("deleteRoutine") {
                    // Find index
                    guard let index = routines.firstIndex(where: { $0.id == id }) else {
                        throw RoutineStorageError.routineNotFound
                    }
                    
                    // Remove routine
                    routines.remove(at: index)
                    
                    // Update version
                    incrementPatchVersion()
                    
                    // Save to storage
                    try saveToStorage()
                    
                    // Log completion
                    logger.log(.info, "Completed operation: deleteRoutine")
                }
                return .success(())
            } catch {
                logger.log(.error, "Operation failed: deleteRoutine - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Reorders a task within a routine
    func reorderTask(inRoutine routineID: String, from: Int, to: Int) -> Result<Void, Error> {
        queue.sync {
            do {
                logger.log(.info, "Starting operation: reorderTask")
                try measureOperation("reorderTask") {
                    // Find routine
                    guard let routineIndex = routines.firstIndex(where: { $0.id == routineID }) else {
                        throw RoutineStorageError.routineNotFound
                    }
                    
                    // Ensure indices are valid
                    guard from >= 0, from < routines[routineIndex].taskUUIDs.count, to >= 0, to <= routines[routineIndex].taskUUIDs.count else {
                        throw RoutineStorageError.invalidIndices
                    }
                    
                    // Reorder task UUIDs
                    var taskUUIDs = routines[routineIndex].taskUUIDs
                    let taskUUID = taskUUIDs.remove(at: from)
                    taskUUIDs.insert(taskUUID, at: to)
                    routines[routineIndex].taskUUIDs = taskUUIDs
                    
                    // Update version
                    incrementPatchVersion()
                    
                    // Save to storage
                    try saveToStorage()
                    
                    // Log completion
                    logger.log(.info, "Completed operation: reorderTask")
                }
                return .success(())
            } catch {
                logger.log(.error, "Operation failed: reorderTask - \(error.localizedDescription)", error: error)
                return .failure(error)
            }
        }
    }
    
    /// Sets the active routine by its ID
    ///
    /// - Parameter id: The UUID of the routine to set as active
    func setActiveRoutine(id: String) {
        queue.sync {
            // Validate that the routine exists
            guard routines.contains(where: { $0.id == id }) else {
                logger.log(.error, "Attempted to set active routine with invalid ID: \(id)")
                return
            }
            
            // Store the active routine ID in UserDefaults
            UserDefaults.standard.set(id, forKey: activeRoutineKey)
            logger.log(.info, "Active routine set to ID: \(id)")
        }
    }
    
    /// Fetches the currently active routine
    ///
    /// - Returns: The active `Routine` if set and exists, otherwise `nil`
    func fetchActiveRoutine() -> Routine? {
        queue.sync {
            guard let activeID = UserDefaults.standard.string(forKey: activeRoutineKey),
                  let routine = fetchRoutine(by: activeID) else {
                logger.log(.info, "No active routine set or routine not found for ID.")
                return nil
            }
            logger.log(.info, "Fetched active routine: \(routine.name)")
            return routine
        }
    }
    
    /// Clears the currently active routine
    func clearActiveRoutine() {
        queue.sync {
            UserDefaults.standard.removeObject(forKey: activeRoutineKey)
            logger.log(.info, "Active routine cleared.")
        }
    }
    
    // MARK: - Private Methods
    
    /// Validates a routine's data
    private func validateRoutine(_ routine: Routine) throws {
        guard !routine.name.isEmpty else {
            throw RoutineStorageError.validationError
        }
        // Additional validations as needed, e.g., tasks exist
        for uuid in routine.taskUUIDs {
            if TaskStorage.shared.fetchTask(by: uuid) == nil {
                throw RoutineStorageError.invalidTaskUUID(uuid)
            }
        }
    }
    
    /// Loads routines from storage
    private func loadFromStorage() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(StorageData.self, from: data)
            self.version = decoded.version
            self.routines = decoded.routines
            logger.log(.debug, "Loaded routines from storage")
        } else {
            // Initialize storage file
            try saveToStorage()
            logger.log(.debug, "Initialized new storage file")
        }
    }
    
    /// Saves routines to storage
    private func saveToStorage() throws {
        let data = StorageData(version: version, routines: routines)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: [.atomicWrite])
        logger.log(.debug, "Saved routines to storage")
    }
    
    /// Increments the patch version
    private func incrementPatchVersion() {
        version = Version(major: version.major, minor: version.minor, patch: version.patch + 1)
        logger.log(.info, "Version update: \(version)")
    }
    
    /// Measures the performance of an operation
    private func measureOperation(_ name: String, operation: () throws -> Void) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()
        
        try operation()
        
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000 // ms
        let memoryDelta = getMemoryUsage() - startMemory
        
        logger.log(.debug, """
            Operation: \(name)
            Duration: \(duration)ms
            Memory Delta: \(memoryDelta)MB
            """)
    }
    
    /// Retrieves current memory usage in MB
    private func getMemoryUsage() -> Double {
        // Placeholder implementation
        // In a real scenario, use appropriate APIs to get memory usage
        return Double.random(in: 0...10)
    }
    
    // MARK: - Testing Methods
    
    #if DEBUG
    /// Resets the storage to its initial state. Intended for testing purposes only.
    func resetStorage() throws {
        queue.sync {
            self.routines = []
            self.version = Version(major: 1, minor: 0, patch: 0)
        }
        try saveToStorage()
        logger.log(.debug, "Storage has been reset for testing")
    }
    #endif
}

/// Represents the structure of the storage file
private struct StorageData: Codable {
    var version: Version
    var routines: [Routine]
}

/// Custom error types for RoutineStorage
enum RoutineStorageError: Error, LocalizedError {
    case routineNotFound
    case validationError
    case invalidTaskUUID(String)
    case invalidIndices
    case storageFailure
    case invalidUUID
    
    var errorDescription: String? {
        switch self {
        case .routineNotFound:
            return "Routine not found."
        case .validationError:
            return "Validation error: Routine name cannot be empty."
        case .invalidTaskUUID(let uuid):
            return "Invalid Task UUID: \(uuid)"
        case .invalidIndices:
            return "Invalid indices for reordering."
        case .storageFailure:
            return "Storage failure: Unable to save or load data."
        case .invalidUUID:
            return "The provided routine UUID string was invalid."
        }
    }
}
