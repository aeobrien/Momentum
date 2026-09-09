import Foundation

/// Manages the selection of tasks based on priority within a routine.
struct TaskSelector {
    
    /// Selects tasks from a routine based on priority and available time.
    ///
    /// - Parameters:
    ///   - routine: The routine from which to select tasks.
    ///   - availableTime: Available time in seconds.
    /// - Returns: Array of selected tasks.
    /// - Throws: RoutineError if priority calculation fails.
    static func selectTasks(from routine: Routine, availableTime: TimeInterval) throws -> [CustomTask] {
        let taskStorage = TaskStorage.shared
        let tasksResult = taskStorage.fetchTasks()
        
        switch tasksResult {
        case .success(let tasks):
            // Create a dictionary for quick access
            let taskDict = Dictionary(uniqueKeysWithValues: tasks.map { ($0.uuid, $0) })
            
            var priorityScores: [(task: CustomTask, score: Double)] = []
            
            for (index, uuid) in routine.taskUUIDs.enumerated() {
                guard let task = taskDict[uuid] else {
                    throw RoutineError.invalidTaskReference(uuid: uuid)
                }
                
                let lastCompletion = routine.metadata.lastUsed
                let repetitionInterval = task.repetitionInterval
                let position = index + 1
                let totalTasks = routine.taskUUIDs.count
                
                let score = try PriorityCalculator.calculatePriority(
                    for: task,
                    lastCompletion: lastCompletion,
                    repetitionInterval: repetitionInterval,
                    position: position,
                    totalTasks: totalTasks
                )
                
                priorityScores.append((task, score))
            }
            
            // Sort by priority score descending
            let sortedTasks = priorityScores.sorted { $0.score > $1.score }.map { $0.task }
            
            // Filter based on available time
            var selectedTasks: [CustomTask] = []
            var remainingTime = availableTime
            
            for task in sortedTasks {
                let taskDuration = TimeInterval(task.minDuration * 60) // Convert minutes to seconds
                if taskDuration <= remainingTime {
                    selectedTasks.append(task)
                    remainingTime -= taskDuration
                }
            }
            
            // Adjust for task dependencies if any (Not implemented here as dependencies are not defined)
            
            // Reorder based on original routine sequence
            let finalSelectedTasks = routine.taskUUIDs.compactMap { uuid in
                selectedTasks.first { $0.uuid == uuid }
            }
            
            return finalSelectedTasks
            
        case .failure(let error):
            throw RoutineError.storageError(description: error.localizedDescription)
        }
    }
}
