/*
// RoutineSetup.swift
import Foundation
import CoreData // <-- Keep imports if other files reference types from here via RoutineSetup
import OSLog    // <-- Keep imports

// Entire file content commented out as it's incompatible with the new CoreDataTaskScheduler
// and uses outdated data models (Routine, CustomTask).

/// RoutineSetup manages the initialization and scheduling of routines
///
/// This class handles routine selection, time calculations, and task scheduling,
/// creating an optimized schedule based on available time and task priorities.
/// It provides the interface between routine storage and execution systems.
///
/// - Important: Requires initialized RoutineStorage and TaskStorage instances
/// - Warning: Time calculations must account for timezone and date boundaries

extension ISO8601DateFormatter {
    static let shared = ISO8601DateFormatter()
}

class RoutineSetup {
    
    /// Current scheduling state including selected routine and end time
    private var schedulingState: SchedulingState
    
    /// Logger instance for Setup System
    private let logger: SetupLogger
    
    /// Initializes RoutineSetup with a selected routine and end time
    ///
    /// - Parameters:
    ///   - selectedRoutine: The routine selected by the user
    ///   - endTime: The target completion time (already adjusted to future)
    init(selectedRoutine: Routine, endTime: Date) {
        self.schedulingState = SchedulingState(
            selectedRoutine: selectedRoutine,
            endTime: endTime,
            availableTime: 0,
            scheduledTasks: []
        )
        self.logger = SetupLogger.setupConfiguration()
    }
    
    /// Calculates available time and schedules tasks for the routine
    ///
    /// - Parameters:
    ///   - endTime: Target completion time (assumed to be in the future)
    ///   - buffer: Time buffer in minutes (default: 20)
    /// - Returns: Scheduled task list or throws an error
    /// - Throws: SchedulingError if time validation fails

    func calculateSchedule(endTime: Date, buffer: Int = 20) throws -> [ScheduledTask] {
        logger.info("Starting schedule calculation for routine: \(schedulingState.selectedRoutine.name)")
        
        // Time Calculation
        let currentTime = Date()
        let availableTime = endTime.timeIntervalSince(currentTime) - TimeInterval(buffer * 60)
        
        logger.debug("""
            Time calculation:
            Current time: \(currentTime)
            End time: \(endTime)
            Available time: \(availableTime) seconds
            Buffer: \(buffer) minutes
            """)
        
        guard availableTime > 0 else {
            logger.error("Insufficient available time: \(availableTime) seconds")
            throw SchedulingError.insufficientTime
        }
        
        schedulingState.availableTime = availableTime
        
        // Fetch tasks from RoutineStorage
        guard let routine = RoutineStorage.shared.fetchRoutine(by: schedulingState.selectedRoutine.id) else {
            logger.error("Routine not found: \(schedulingState.selectedRoutine.id)")
            throw SchedulingError.routineLoadError
        }
        
        let taskUUIDs = routine.taskUUIDs
        let allTasksResult = TaskStorage.shared.fetchTasks()
        
        let allTasks: [CustomTask]
        switch allTasksResult {
        case .success(let tasks):
            allTasks = tasks
        case .failure(let error):
            logger.error("Failed to fetch tasks: \(error.localizedDescription)")
            throw SchedulingError.schedulingFailure
        }
        
        var customTasks: [CustomTask] = []
        for uuid in taskUUIDs {
            if let task = TaskStorage.shared.fetchTask(by: uuid) {
                customTasks.append(task)
            } else {
                logger.warning("Task not found with UUID: \(uuid)")
                throw SchedulingError.invalidTaskReference(uuid: uuid)
            }
        }
        
        // Task Prioritization and Selection
        let prioritizedTasks = try prioritizeTasks(tasks: customTasks, availableTime: availableTime)
        
        schedulingState.scheduledTasks = prioritizedTasks
        logger.info("Schedule calculation completed successfully")
        
        return prioritizedTasks
    }
    
    /// Prioritizes and selects tasks based on available time and task priorities
    ///
    /// - Parameters:
    ///   - tasks: List of all tasks in the routine
    ///   - availableTime: Total available time for scheduling
    /// - Returns: List of scheduled tasks
    /// - Throws: SchedulingError if scheduling fails
    private func prioritizeTasks(tasks: [CustomTask], availableTime: TimeInterval) throws -> [ScheduledTask] {
        // Phase 1: Essential Tasks
        let essentialTasks = tasks.filter { ($0.essentiality ?? 0) == Essentiality.essential.value }
        var scheduledTasks: [ScheduledTask] = []
        var remainingTime = availableTime
        
        for task in essentialTasks {
            let duration = TimeInterval(task.minDuration * 60) // Convert minutes to seconds
            if remainingTime >= duration {
                let scheduledTask = ScheduledTask(
                    task: task,
                    allocatedDuration: duration,
                    isFlexible: task.minDuration != task.maxDuration
                )
                scheduledTasks.append(scheduledTask)
                remainingTime -= duration
            } else {
                logger.error("Insufficient time for essential task: \(task.taskName)")
                throw SchedulingError.insufficientTime
            }
        }
        
        // Phase 2: Core Tasks
        let coreTasks = tasks.filter { ($0.essentiality ?? 0) == Essentiality.core.value }
        let sortedCoreTasks = try coreTasks.sorted {
            let score1 = try PriorityCalculator.calculatePriority(
                for: $0,
                lastCompletion: $0.lastCompleted.flatMap { ISO8601DateFormatter.shared.date(from: $0) },
                repetitionInterval: $0.repetitionInterval,
                position: $0.order ?? 0,
                totalTasks: tasks.count
            )
            let score2 = try PriorityCalculator.calculatePriority(
                for: $1,
                lastCompletion: $1.lastCompleted.flatMap { ISO8601DateFormatter.shared.date(from: $0) },
                repetitionInterval: $1.repetitionInterval,
                position: $1.order ?? 0,
                totalTasks: tasks.count
            )
            return score1 > score2
        }
        
        for task in sortedCoreTasks {
            let duration = TimeInterval(task.minDuration * 60)
            if remainingTime >= duration {
                let scheduledTask = ScheduledTask(
                    task: task,
                    allocatedDuration: duration,
                    isFlexible: task.minDuration != task.maxDuration
                )
                scheduledTasks.append(scheduledTask)
                remainingTime -= duration
            }
        }
        
        // Phase 3: Non-essential Tasks
        let nonEssentialTasks = tasks.filter { ($0.essentiality ?? 0) == Essentiality.nonEssential.value }
        let sortedNonEssentialTasks = try nonEssentialTasks.sorted {
            let score1 = try PriorityCalculator.calculatePriority(
                for: $0,
                lastCompletion: $0.lastCompleted.flatMap { ISO8601DateFormatter.shared.date(from: $0) },
                repetitionInterval: $0.repetitionInterval,
                position: $0.order ?? 0,
                totalTasks: tasks.count
            )
            let score2 = try PriorityCalculator.calculatePriority(
                for: $1,
                lastCompletion: $1.lastCompleted.flatMap { ISO8601DateFormatter.shared.date(from: $0) },
                repetitionInterval: $1.repetitionInterval,
                position: $1.order ?? 0,
                totalTasks: tasks.count
            )
            return score1 > score2
        }
        
        for task in sortedNonEssentialTasks {
            let duration = TimeInterval(task.minDuration * 60)
            if remainingTime >= duration {
                let scheduledTask = ScheduledTask(
                    task: task,
                    allocatedDuration: duration,
                    isFlexible: task.minDuration != task.maxDuration
                )
                scheduledTasks.append(scheduledTask)
                remainingTime -= duration
            }
        }
        
        // Duration Extension for Flexible Tasks
        scheduledTasks = try extendDurationsIfPossible(scheduledTasks: scheduledTasks, availableTime: remainingTime)
        
        return scheduledTasks
    }
    
    /// Extends durations of flexible tasks if there is remaining time
    ///
    /// - Parameters:
    ///   - scheduledTasks: Currently scheduled tasks
    ///   - availableTime: Remaining available time
    /// - Returns: Updated list of scheduled tasks with extended durations
    /// - Throws: SchedulingError if extension fails
    private func extendDurationsIfPossible(scheduledTasks: [ScheduledTask], availableTime: TimeInterval) throws -> [ScheduledTask] {
        var updatedTasks = scheduledTasks
        var remainingTime = availableTime
        
        // Identify flexible tasks
        let flexibleTasks = updatedTasks.filter { $0.isFlexible }
        let totalScore: Double = try flexibleTasks.reduce(0.0) { (partialResult, scheduledTask) in
            let priority = try PriorityCalculator.calculatePriority(
                for: scheduledTask.task,
                lastCompletion: scheduledTask.task.lastCompleted.flatMap { lastCompletedString in
                    ISO8601DateFormatter.shared.date(from: lastCompletedString)
                },
                repetitionInterval: scheduledTask.task.repetitionInterval,
                position: scheduledTask.task.order ?? 0,
                totalTasks: scheduledTasks.count
            )
            return partialResult + priority
        }

        
        guard totalScore > 0 else {
            return updatedTasks
        }
        
        // Extend durations based on priority
        for (index, task) in updatedTasks.enumerated() {
            guard task.isFlexible else { continue }
            
            let potentialExtension = TimeInterval(task.task.maxDuration - task.task.minDuration) * 60
            let taskScore: Double
            do {
                taskScore = try PriorityCalculator.calculatePriority(
                    for: task.task,
                    lastCompletion: task.task.lastCompleted.flatMap { ISO8601DateFormatter.shared.date(from: $0) },
                    repetitionInterval: task.task.repetitionInterval,
                    position: task.task.order ?? 0,
                    totalTasks: scheduledTasks.count
                ) * (1 - Double(task.task.order ?? 0) / Double(scheduledTasks.count))
            } catch {
                logger.error("Failed to calculate priority for task '\(task.task.taskName)': \(error.localizedDescription)")
                throw error
            }
            
            let extensionTime = min(potentialExtension, (remainingTime * taskScore) / totalScore)
            updatedTasks[index].allocatedDuration += extensionTime
            remainingTime -= extensionTime
            
            if remainingTime <= 0 {
                break
            }
        }
        
        logger.debug("""
            Duration extension results:
            Total tasks: \(updatedTasks.count)
            Available time after extension: \(remainingTime) seconds
            """)
        
        return updatedTasks
    }
}

*/
