import Foundation
import CoreData

/// ViewModel for managing routines.
class RoutineViewModel: ObservableObject {
    @Published var routines: [Routine] = []
    @Published var selectedRoutine: Routine?
    @Published var errorMessage: String?
    
    private let routineStorage = RoutineStorageCoreData.shared
    private let logger = AppLogger.create(subsystem: "com.app.RoutineViewModel", category: "ViewModel")
    
    init() {
        fetchRoutines()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDataStoreChange),
            name: .dataStoreDidChange,
            object: nil
        )
    }
    
    @objc private func handleDataStoreChange() {
        logger.info("Data store changed, refreshing routines")
        // Clear selected routine as it may not exist in the new store
        selectedRoutine = nil
        fetchRoutines()
    }
    
    /// Fetches all routines from storage.
    func fetchRoutines() {
        let result = routineStorage.fetchRoutines()
        switch result {
        case .success(let fetchedRoutines):
            DispatchQueue.main.async {
                self.routines = fetchedRoutines
            }
            logger.info("Successfully fetched \(fetchedRoutines.count) routines")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to fetch routines", error: error)
        }
    }
    
    /// Creates a new routine.
    ///
    /// - Parameters:
    ///   - name: Name of the routine.
    ///   - taskUUIDs: Array of task UUIDs in order.
    func createRoutine(name: String, taskUUIDs: [String]) {
        let newRoutine = Routine(
            id: UUID().uuidString,
            name: name,
            createdOn: Date(),
            taskUUIDs: taskUUIDs,
            metadata: RoutineMetadata(
                lastUsed: Date(),
                totalCompletions: 0,
                averageCompletionTime: 0
            )
        )
        
        let result = routineStorage.createRoutine(newRoutine)
        switch result {
        case .success(let routine):
            DispatchQueue.main.async {
                self.routines.append(routine)
            }
            logger.info("Successfully created routine: \(name)")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to create routine: \(name)", error: error)
        }
    }
    
    /// Updates an existing routine.
    ///
    /// - Parameter routine: The updated routine.
    func updateRoutine(_ routine: Routine) {
        let result = routineStorage.updateRoutine(routine)
        switch result {
        case .success(let updatedRoutine):
            DispatchQueue.main.async {
                if let index = self.routines.firstIndex(where: { $0.id == updatedRoutine.id }) {
                    self.routines[index] = updatedRoutine
                }
            }
            logger.info("Successfully updated routine: \(routine.name)")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to update routine: \(routine.name)", error: error)
        }
    }
    
    /// Deletes a routine.
    ///
    /// - Parameter routine: Routine to delete.
    func deleteRoutine(_ routine: Routine) {
        let result = routineStorage.deleteRoutine(id: routine.id)
        switch result {
        case .success:
            DispatchQueue.main.async {
                self.routines.removeAll { $0.id == routine.id }
            }
            logger.info("Successfully deleted routine: \(routine.name)")
        case .failure(let error):
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to delete routine: \(routine.name)", error: error)
        }
    }
    
    /// Reorders a task within a routine.
    ///
    /// - Parameters:
    ///   - routineID: The ID of the routine to modify.
    ///   - from: The source index.
    ///   - to: The destination index.
    func reorderTask(inRoutine routineID: String, from: Int, to: Int) -> Result<Void, Error> {
        return routineStorage.reorderTask(inRoutine: routineID, from: from, to: to)
    }
}
