import Foundation

/// Protocol defining the interface for routine storage operations.
protocol RoutineStorageInterface {
    /// Creates a new routine.
    ///
    /// - Parameter routine: The `Routine` object to be created.
    /// - Returns: A `Result` containing the created `Routine` or an `Error`.
    func createRoutine(_ routine: Routine) -> Result<Routine, Error>
    
    /// Fetches all routines.
    ///
    /// - Returns: A `Result` containing an array of `Routine` objects or an `Error`.
    func fetchRoutines() -> Result<[Routine], Error>
    
    /// Updates an existing routine.
    ///
    /// - Parameter routine: The `Routine` object with updated data.
    /// - Returns: A `Result` containing the updated `Routine` or an `Error`.
    func updateRoutine(_ routine: Routine) -> Result<Routine, Error>
    
    /// Deletes a routine by its ID.
    ///
    /// - Parameter id: The ID of the routine to delete.
    /// - Returns: A `Result` indicating success (`Void`) or an `Error`.
    func deleteRoutine(id: String) -> Result<Void, Error>
    
    /// Reorders a task within a routine.
    ///
    /// - Parameters:
    ///   - routineID: The ID of the routine containing the task.
    ///   - from: The original index of the task.
    ///   - to: The new index for the task.
    /// - Returns: A `Result` indicating success (`Void`) or an `Error`.
    func reorderTask(inRoutine routineID: String, from: Int, to: Int) -> Result<Void, Error>
}
