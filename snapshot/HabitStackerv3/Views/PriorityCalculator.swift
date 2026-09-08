import Foundation

/// Calculates priority scores for tasks within a routine.
struct PriorityCalculator {
    
    /// Calculates the priority score for a task.
    ///
    /// - Parameters:
    ///   - task: The task for which to calculate the priority.
    ///   - lastCompletion: Date of the last completion.
    ///   - repetitionInterval: Target frequency for task completion in seconds.
    ///   - position: Current position in the routine.
    ///   - totalTasks: Total number of tasks in the routine.
    /// - Returns: Priority score.
    static func calculatePriority(
        for task: CustomTask,
        lastCompletion: Date?,
        repetitionInterval: Int?,
        position: Int,
        totalTasks: Int
    ) throws -> Double {
        // Base Priority (Essentiality Tier)
        guard let essentiality = task.essentiality else {
            throw RoutineError.priorityCalculationError(description: "Essentiality not defined for task \(task.uuid)")
        }
        
        // Time-Based Factors
        let now = Date()
        let lastCompletionDate = lastCompletion ?? now
        let timeSinceLastCompletion = now.timeIntervalSince(lastCompletionDate)
        
        guard let repetition = repetitionInterval, repetition > 0 else {
            throw RoutineError.priorityCalculationError(description: "Invalid repetition interval for task \(task.uuid)")
        }
        
        let timeFactor = timeSinceLastCompletion / TimeInterval(repetition)
        
        // Position Factor
        let positionFactor = 1.0 - (Double(position) / Double(totalTasks))
        
        // Priority Score Calculation
        let priorityScore = Double(essentiality) * (1.0 + timeFactor + positionFactor)
        
        return priorityScore
    }
}
