import Foundation
import CoreData
import OSLog

// MARK: - Supporting Structures


/// Represents a potential action during the enhancement phase.
enum EnhancementActionType {
    case addTask
    case addIncrement
}

struct EnhancementAction: Comparable {
    let type: EnhancementActionType
    let taskID: NSManagedObjectID
    let taskNameForSort: String
    let priorityScore: Double
    let cost: TimeInterval // Duration in seconds (minDuration for AddTask, 300 for AddIncrement)
    var remainingIncrements: Int? // Only for AddIncrement
    let minDuration: TimeInterval
    let maxDuration: TimeInterval

    // Comparable for sorting: Higher score first, then lower cost, then original order (using name)
    static func < (lhs: EnhancementAction, rhs: EnhancementAction) -> Bool {
        if lhs.priorityScore != rhs.priorityScore {
            return lhs.priorityScore < rhs.priorityScore // Higher score is "greater"
        }
        if lhs.cost != rhs.cost {
            return lhs.cost > rhs.cost // Lower cost is "greater" for sorting (higher priority)
        }
        // Use stored task name as final tie-breaker
        return lhs.taskNameForSort > rhs.taskNameForSort // Earlier name is "greater"
    }

    static func == (lhs: EnhancementAction, rhs: EnhancementAction) -> Bool {
        lhs.taskID == rhs.taskID && lhs.type == rhs.type
    }

    // Initializer to capture necessary data from CDTask
    init(type: EnhancementActionType, task: CDTask, priorityScore: Double, cost: TimeInterval, remainingIncrements: Int? = nil) {
        self.type = type
        self.taskID = task.objectID
        self.taskNameForSort = task.taskName ?? ""
        self.priorityScore = priorityScore
        self.cost = cost
        self.remainingIncrements = remainingIncrements
        // Store durations directly
        self.minDuration = TimeInterval(task.minDuration * 60)
        self.maxDuration = TimeInterval(task.maxDuration * 60)
    }
}


// MARK: - CoreDataTaskScheduler

struct CoreDataTaskScheduler {

    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CoreDataTaskScheduler")
    private static let secondsInDay: TimeInterval = 86400
    private static let incrementDuration: TimeInterval = 300 // 5 minutes in seconds

    // Initializer requires context
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Generates a prioritized and time-constrained schedule of tasks.
    /// - Parameters:
    ///   - routine: The CDRoutine to schedule tasks from.
    ///   - availableTime: Total available time in seconds.
    /// - Returns: An array of ScheduledTask objects, sorted by their original routine order, or throws a SchedulingError.
    func generateSchedule(for routine: CDRoutine, availableTime: TimeInterval) throws -> [ScheduledTask] {
        logger.info("Starting schedule generation for routine '\(routine.name ?? "Unnamed")' with available time: \(availableTime / 60, format: .fixed(precision: 1)) mins.")

        // --- Stage 0: Preparation ---
        guard let relations = routine.taskRelations as? Set<CDRoutineTask>, !relations.isEmpty else {
            logger.warning("Routine '\(routine.name ?? "Unnamed")' has no tasks.")
            return []
        }
        let sortedRelations = relations.sorted { $0.order < $1.order }
        let allTasksInOrderIDs = sortedRelations.compactMap { $0.task?.objectID }
        // Create a map from ObjectID to original CDTask for easy lookup if needed,
        // ensuring they are accessed via the scheduler's context.
        let taskMap = Dictionary(uniqueKeysWithValues: sortedRelations.compactMap { relation -> (NSManagedObjectID, CDTask)? in
            guard let task = relation.task else { return nil }
            // Ensure task is accessed via the correct context
            guard let taskInContext = context.object(with: task.objectID) as? CDTask else {
                logger.error("Failed to fetch task with ID \(task.objectID) in the provided context.")
                return nil
            }
            return (task.objectID, taskInContext)
        })

        // *** ADDED CONTEXT/FAULT CHECKS (POST-MAP CREATION) ***
        logger.debug("Scheduler Context: \(String(describing: context))")
        logger.debug("Routine Context: \(String(describing: routine.managedObjectContext))")
        if routine.managedObjectContext != context {
            logger.error("CRITICAL: Routine context (\(String(describing: routine.managedObjectContext))) does NOT match scheduler context (\(String(describing: context)))!")
            // Potentially throw an error or handle this mismatch
        }
        logger.debug("TaskMap populated with \(taskMap.count) tasks. Verifying tasks in map...")
        var mapTaskContextMismatch = false
        var mapTaskFault = false
        for (id, task) in taskMap {
            if task.managedObjectContext != context {
                 logger.error("CRITICAL: Task '\(task.taskName ?? "\(id)")' in map has DIFFERENT context (\(String(describing: task.managedObjectContext))) than scheduler context (\(String(describing: context)))!")
                 mapTaskContextMismatch = true
            }
            if task.isFault {
                logger.warning("Task '\(task.taskName ?? "\(id)")' is FAULT in initial map population.")
                mapTaskFault = true
            }
        }
        if mapTaskContextMismatch { logger.error("Map Verification: Context Mismatch DETECTED in taskMap!") }
        if mapTaskFault { logger.warning("Map Verification: Faulted Task DETECTED in taskMap!") }
        logger.debug("Map Verification Complete.")
        // *** END ADDED CONTEXT/FAULT CHECKS ***

        // --- Stage 1: Initial Task Selection (Eligibility & Min Duration) ---
        let (stage1ScheduledTaskIDs, stage1RemainingTime, eligibleUnscheduledIDs) = try performStage1Selection(
            taskMap: taskMap,
            tasksInOrderIDs: allTasksInOrderIDs,
            availableTime: availableTime
        )

        // --- Stage 2: Iterative Enhancement (Distributing Remaining Time) ---
        let (tasksWithFinalDurations) = try performStage2Enhancement(
            taskMap: taskMap,
            initialScheduledIDs: stage1ScheduledTaskIDs,
            initialRemainingTime: stage1RemainingTime,
            eligibleUnscheduledIDs: eligibleUnscheduledIDs
        )

        // --- Stage 3: Final Ordering and Output ---
        let finalSchedule = finalizeSchedule(
            tasksWithDurations: tasksWithFinalDurations,
            originalOrderIDs: allTasksInOrderIDs,
            taskMap: taskMap
        )

        let totalAllocatedTime = finalSchedule.reduce(0) { $0 + $1.allocatedDuration }
        logger.info("Schedule generation complete. Scheduled \(finalSchedule.count) tasks. Total allocated time: \(totalAllocatedTime / 60, format: .fixed(precision: 1)) mins.")

        return finalSchedule
    }

    // Stage 1: Initial Task Selection
    private func performStage1Selection(
        taskMap: [NSManagedObjectID: CDTask], // Map for quick lookup
        tasksInOrderIDs: [NSManagedObjectID], // Original order
        availableTime: TimeInterval
    ) throws -> (scheduledTaskIDs: Set<NSManagedObjectID>, remainingTime: TimeInterval, eligibleUnscheduledIDs: [NSManagedObjectID: Double]) {
        logger.debug("Performing Stage 1: Initial Selection for \(tasksInOrderIDs.count) tasks with \(availableTime / 60, format: .fixed(precision: 1)) mins...")
        var scheduledTaskIDs = Set<NSManagedObjectID>() // Use Set of ObjectIDs
        var remainingTime = availableTime
        var eligibleUnscheduledIDs = [NSManagedObjectID: Double]() // ObjectID -> Priority Score
        var essentialTaskIDs = [(id: NSManagedObjectID, duration: TimeInterval)]()

        // --- Pass 1: Eligibility Check & Essential Task Identification ---
        logger.debug("Stage 1 - Pass 1: Checking eligibility and identifying Essential tasks...")
        for taskID in tasksInOrderIDs {
            logger.debug("Processing Task ID: \(taskID)")
            guard let task = taskMap[taskID] else {
                logger.warning("Task with ID \(taskID) not found in map during Stage 1 Pass 1. Skipping.")
                continue
            }

            // *** ADDED VALIDITY CHECKS (PRE-ELIGIBILITY) ***
            var taskIsInvalid = false
            if task.isFault {
                logger.error("CRITICAL PRE-CHECK: Task '\(task.taskName ?? "\(taskID)")' is a FAULT before eligibility check!")
                taskIsInvalid = true
                // Optionally try to refresh: context.refresh(task, mergeChanges: true)
                // If refreshing, ensure it doesn't throw and potentially reset taskIsInvalid if successful.
            }
            if task.managedObjectContext != context {
                logger.error("CRITICAL PRE-CHECK: Task '\(task.taskName ?? "\(taskID)")' context (\(String(describing: task.managedObjectContext))) MISMATCHES scheduler context (\(String(describing: context))) before eligibility check!")
                taskIsInvalid = true
            }
            // If the task is invalid, maybe skip eligibility check entirely? Or let it potentially crash to confirm.
            // For now, we log the error and proceed to see if the crash follows immediately.
            // *** END ADDED VALIDITY CHECKS ***

            let eligible = isTaskEligible(task: task)
            if eligible {
                let score = calculatePriorityScore(task: task, eligible: true)
                let minDurationSeconds = TimeInterval(task.minDuration * 60)

                if task.essentiality == 3 { // Essential
                    essentialTaskIDs.append((task.objectID, minDurationSeconds))
                } else if task.essentiality == 2 || task.essentiality == 1 { // Core or Optional
                    eligibleUnscheduledIDs[task.objectID] = score
                    logger.trace("- Eligible Non-Essential: '\(task.taskName ?? "Unnamed")', Score: \(score, format: .fixed(precision: 2)), MinDuration: \(minDurationSeconds/60)m")
                } else {
                    logger.warning("Task '\(task.taskName ?? "Unnamed")' has invalid essentiality: \(task.essentiality). Skipping.")
                }
            } else {
                logger.trace("- Ineligible: '\(task.taskName ?? "Unnamed")'")
            }
        }

        // --- Pass 2: Schedule Essential Tasks ---
        logger.debug("Stage 1 - Pass 2: Scheduling \(essentialTaskIDs.count) Essential tasks...")
        for essential in essentialTaskIDs {
            guard let task = taskMap[essential.id] else {
                logger.warning("Essential Task with ID \(essential.id) not found in map during Stage 1 Pass 2. Skipping.")
                continue
            }
            if remainingTime >= essential.duration {
                scheduledTaskIDs.insert(essential.id)
                remainingTime -= essential.duration
                logger.trace("- Added Essential: '\(task.taskName ?? "Unnamed")' (\(essential.duration/60)m). Remaining time: \(remainingTime / 60, format: .fixed(precision: 1))m")
            } else {
                // Allow a small tolerance for timing edge cases (1 minute)
                let availableTime = remainingTime
                let shortfall = essential.duration - remainingTime
                let toleranceSeconds: TimeInterval = 60 // 1 minute tolerance
                
                if shortfall <= toleranceSeconds {
                    // Within tolerance - schedule it anyway
                    scheduledTaskIDs.insert(essential.id)
                    remainingTime = 0 // Use up all remaining time
                    logger.warning("Essential task '\(task.taskName ?? "Unnamed")' scheduled with minor shortfall. Required: \(essential.duration/60)m, Available: \(availableTime/60)m, Shortfall: \(shortfall/60)m")
                } else {
                    // Beyond tolerance - this is a real problem
                    logger.error("Insufficient time for Essential task '\(task.taskName ?? "Unnamed")'. Required: \(essential.duration/60)m, Available: \(availableTime/60)m, Shortfall: \(shortfall/60)m")
                    throw SchedulingError.insufficientTime
                }
            }
        }

        // --- Pass 3: Prioritized Selection for Core Tasks ---
        let coreTaskIDs = eligibleUnscheduledIDs
            .filter { taskMap[$0.key]?.essentiality == 2 }
            .sorted { item1, item2 in
                guard let task1 = taskMap[item1.key], let task2 = taskMap[item2.key] else { return false } // Should not happen if map is correct
                // Sort by: Score (desc), LastCompleted (asc), Original Order (asc)
                if item1.value != item2.value {
                    return item1.value > item2.value // Higher score first
                }
                let date1 = task1.lastCompleted ?? Date.distantPast
                let date2 = task2.lastCompleted ?? Date.distantPast
                if date1 != date2 {
                    return date1 < date2 // Older date first
                }
                // Use original order IDs for tie-breaking
                let index1 = tasksInOrderIDs.firstIndex(of: item1.key) ?? Int.max
                let index2 = tasksInOrderIDs.firstIndex(of: item2.key) ?? Int.max
                return index1 < index2 // Lower original index first
            }

        logger.debug("Stage 1 - Pass 3: Selecting from \(coreTaskIDs.count) eligible Core tasks...")
        for item in coreTaskIDs {
            let taskID = item.key // Access the NSManagedObjectID
            let score = item.value // Access the score
            guard let task = taskMap[taskID] else {
                logger.warning("Core Task with ID \(taskID) not found in map during Stage 1 Pass 3. Skipping.")
                continue
            }
            let duration = TimeInterval(task.minDuration * 60)
            if remainingTime >= duration {
                scheduledTaskIDs.insert(taskID)
                remainingTime -= duration
                eligibleUnscheduledIDs.removeValue(forKey: taskID) // Remove using the key
                logger.trace("- Added Core: '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Dur: \(duration/60)m). Remaining time: \(remainingTime / 60, format: .fixed(precision: 1))m")
            } else {
                // Check if we're within tolerance for this core task
                let shortfall = duration - remainingTime
                let toleranceSeconds: TimeInterval = 60 // 1 minute tolerance
                
                if shortfall <= toleranceSeconds && remainingTime > 0 {
                    // Within tolerance - schedule it anyway
                    scheduledTaskIDs.insert(taskID)
                    let oldRemaining = remainingTime
                    remainingTime = 0 // Use up all remaining time
                    eligibleUnscheduledIDs.removeValue(forKey: taskID)
                    logger.trace("- Added Core (tolerance): '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Dur: \(duration/60)m, Available: \(oldRemaining/60)m, Shortfall: \(shortfall/60)m)")
                } else {
                    logger.trace("- Skipped Core (Time): '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Dur: \(duration/60)m)")
                }
                // Don't break, continue checking other core tasks
            }
        }

        // --- Pass 4: Prioritized Selection for Optional Tasks ---
        let optionalTaskIDs = eligibleUnscheduledIDs // Remaining are optional (or core that didn't fit)
            .filter { taskMap[$0.key]?.essentiality == 1 }
            .sorted { item1, item2 in
                guard let task1 = taskMap[item1.key], let task2 = taskMap[item2.key] else { return false }
                // Sort by: Score (desc), LastCompleted (asc), Original Order (asc)
                if item1.value != item2.value {
                    return item1.value > item2.value // Higher score first
                }
                let date1 = task1.lastCompleted ?? Date.distantPast
                let date2 = task2.lastCompleted ?? Date.distantPast
                if date1 != date2 {
                    return date1 < date2 // Older date first
                }
                let index1 = tasksInOrderIDs.firstIndex(of: item1.key) ?? Int.max
                let index2 = tasksInOrderIDs.firstIndex(of: item2.key) ?? Int.max
                return index1 < index2 // Lower original index first
            }

        logger.debug("Stage 1 - Pass 4: Selecting from \(optionalTaskIDs.count) eligible Optional tasks...")
        for item in optionalTaskIDs {
            let taskID = item.key // Access the NSManagedObjectID
            let score = item.value // Access the score
            guard let task = taskMap[taskID] else {
                logger.warning("Optional Task with ID \(taskID) not found in map during Stage 1 Pass 4. Skipping.")
                continue
            }
            let duration = TimeInterval(task.minDuration * 60)
            if remainingTime >= duration {
                scheduledTaskIDs.insert(taskID)
                remainingTime -= duration
                eligibleUnscheduledIDs.removeValue(forKey: taskID) // Remove using the key
                logger.trace("- Added Optional: '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Dur: \(duration/60)m). Remaining time: \(remainingTime / 60, format: .fixed(precision: 1))m")
            } else {
                // Check if we're within tolerance for this optional task
                let shortfall = duration - remainingTime
                let toleranceSeconds: TimeInterval = 60 // 1 minute tolerance
                
                if shortfall <= toleranceSeconds && remainingTime > 0 {
                    // Within tolerance - schedule it anyway
                    scheduledTaskIDs.insert(taskID)
                    let oldRemaining = remainingTime
                    remainingTime = 0 // Use up all remaining time
                    eligibleUnscheduledIDs.removeValue(forKey: taskID)
                    logger.trace("- Added Optional (tolerance): '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Dur: \(duration/60)m, Available: \(oldRemaining/60)m, Shortfall: \(shortfall/60)m)")
                } else {
                    logger.trace("- Skipped Optional (Time): '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Dur: \(duration/60)m)")
                }
                // Don't break, continue checking other optional tasks
            }
        }

        logger.info("Stage 1 complete. \(scheduledTaskIDs.count) tasks initially selected. Remaining time for enhancement: \(remainingTime / 60, format: .fixed(precision: 1)) mins.")
        // Return the Set of scheduled task IDs, remaining time, and the dictionary of eligible task IDs that *were not* scheduled
        return (scheduledTaskIDs, remainingTime, eligibleUnscheduledIDs)
    }

    // Stage 2: Iterative Enhancement
    private func performStage2Enhancement(
        taskMap: [NSManagedObjectID: CDTask], // Map for fetching tasks
        initialScheduledIDs: Set<NSManagedObjectID>,
        initialRemainingTime: TimeInterval,
        eligibleUnscheduledIDs: [NSManagedObjectID: Double] // ObjectID -> Priority Score
    ) throws -> [NSManagedObjectID: TimeInterval] { // ObjectID -> Allocated Duration
        logger.debug("Performing Stage 2: Iterative Enhancement with \(initialRemainingTime / 60, format: .fixed(precision: 1)) mins remaining...")

        var remainingTime = initialRemainingTime
        // Initialize final durations with minDuration for initially scheduled tasks
        var tasksWithFinalDurations = Dictionary(uniqueKeysWithValues: initialScheduledIDs.compactMap { id -> (NSManagedObjectID, TimeInterval)? in
            guard let task = taskMap[id] else { return nil }
            return (id, TimeInterval(task.minDuration * 60))
        })
        var enhancementCandidates: [EnhancementAction] = []

        // --- Populate Initial Candidates ---
        logger.debug("Stage 2 - Populating initial enhancement candidates...")
        // Add "AddIncrement" candidates for tasks already scheduled
        for taskID in initialScheduledIDs {
            guard let task = taskMap[taskID] else {
                logger.warning("Task \(taskID) not found in map when populating Stage 2 increments. Skipping.")
                continue
            }
            if task.maxDuration > task.minDuration {
                let maxIncrements = Int((task.maxDuration - task.minDuration) / 5)
                if maxIncrements > 0 {
                    // Use score from eligibleUnscheduledIDs if available (Core/Optional), else calculate/use default for Essential
                    let score = eligibleUnscheduledIDs[taskID] ?? calculatePriorityScore(task: task, eligible: true) // Recalculate for Essential or if missing
                    let candidate = EnhancementAction(type: .addIncrement, task: task, priorityScore: score, cost: Self.incrementDuration, remainingIncrements: maxIncrements)
                    enhancementCandidates.append(candidate)
                    logger.trace("- Add Inc Candidate: '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Increments: \(maxIncrements))")
                }
            }
        }
        // Add "AddTask" candidates for eligible but unscheduled tasks
        for (taskID, score) in eligibleUnscheduledIDs {
            guard let task = taskMap[taskID] else {
                logger.warning("Task \(taskID) not found in map when populating Stage 2 add tasks. Skipping.")
                continue
            }
            let minDurationSeconds = TimeInterval(task.minDuration * 60)
            // Only add if the task *could* potentially fit
            if minDurationSeconds <= remainingTime {
                let candidate = EnhancementAction(type: .addTask, task: task, priorityScore: score, cost: minDurationSeconds)
                enhancementCandidates.append(candidate)
                logger.trace("- Add Task Candidate: '\(task.taskName ?? "Unnamed")' (Score: \(score, format: .fixed(precision: 2)), Cost: \(minDurationSeconds/60)m)")
            }
        }

        // --- Enhancement Loop ---
        logger.debug("Stage 2 - Starting enhancement loop...")
        while remainingTime >= Self.incrementDuration { // Loop while there's enough time for at least one increment
            // Filter candidates that are too expensive for remaining time
            let affordableCandidates = enhancementCandidates.filter { $0.cost <= remainingTime }

            // Sort by: Priority Score (desc), Cost (asc), Original Order (asc)
            guard let bestActionIndex = affordableCandidates.indices.max(by: { affordableCandidates[$0] < affordableCandidates[$1] }) else {
                logger.debug("No affordable enhancement candidates found. Exiting loop.")
                break // No affordable candidates left
            }
            var bestAction = affordableCandidates[bestActionIndex] // Make mutable for modification
            let taskID = bestAction.taskID // Use the stored taskID
            guard let task = taskMap[taskID] else {
                logger.error("Task \(taskID) for best action not found in map! Skipping action.")
                // Remove this invalid candidate to avoid infinite loop
                enhancementCandidates.remove(at: bestActionIndex)
                continue
            }

            // Break down logging components to help compiler
            let remTimeMins = remainingTime / 60.0
            let taskNameStr = task.taskName ?? "Unnamed"
            let actionTypeStr = "\(bestAction.type)" // Explicitly convert enum
            let scoreVal = bestAction.priorityScore
            let costMins = bestAction.cost / 60.0

            logger.trace("Loop: Remaining Time: \(remTimeMins, format: .fixed(precision: 1))m. Best Action: \(actionTypeStr) for '\(taskNameStr)' (Score: \(scoreVal, format: .fixed(precision: 2)), Cost: \(costMins, format: .fixed(precision: 1))m)")

            // Execute the best action
            remainingTime -= bestAction.cost

            if bestAction.type == .addTask {
                // Add task to the dictionary with its min duration
                tasksWithFinalDurations[taskID] = bestAction.cost
                logger.debug("  - Executed: Added Task '\(taskNameStr)'. Remaining time: \(remainingTime / 60, format: .fixed(precision: 1))m")

                // If the newly added task is variable, add its increment candidate
                if bestAction.maxDuration > bestAction.minDuration {
                    let maxIncrements = Int((bestAction.maxDuration - bestAction.minDuration) / Self.incrementDuration) // Calculate from stored durations
                    if maxIncrements > 0 {
                        // Create EnhancementAction using its initializer - needs the original task object temporarily
                        let incrementCandidate = EnhancementAction(type: .addIncrement, task: task, priorityScore: bestAction.priorityScore, cost: Self.incrementDuration, remainingIncrements: maxIncrements)
                        enhancementCandidates.append(incrementCandidate)
                        logger.trace("  - Added new Inc Candidate for '\(taskNameStr)'")
                    }
                }
                // Remove the AddTask action from candidates (it's done)
                enhancementCandidates.removeAll { $0.taskID == taskID && $0.type == .addTask } // Remove based on taskID and type

            } else { // .addIncrement
                // Increase allocated duration for the task
                let currentDuration = tasksWithFinalDurations[taskID] ?? bestAction.minDuration // Use stored minDuration as fallback
                tasksWithFinalDurations[taskID] = currentDuration + Self.incrementDuration
                bestAction.remainingIncrements? -= 1
                logger.debug("  - Executed: Incremented '\(taskNameStr)' by 5m. Total: \(tasksWithFinalDurations[taskID]! / 60)m. Remaining time: \(remainingTime / 60, format: .fixed(precision: 1))m")

                // Find the original candidate to update/remove
                if let index = enhancementCandidates.firstIndex(where: { $0.taskID == taskID && $0.type == .addIncrement }) {
                    if bestAction.remainingIncrements ?? 0 > 0 {
                        // Update the candidate with decremented count
                        enhancementCandidates[index] = bestAction
                        logger.trace("  - Updated Inc Candidate for '\(taskNameStr)'. Remaining increments: \(bestAction.remainingIncrements!)")
                    } else {
                        // Remove the candidate if no increments left
                        enhancementCandidates.remove(at: index)
                        logger.trace("  - Removed Inc Candidate for '\(taskNameStr)' (no increments left)")
                    }
                } else {
                    logger.warning("Could not find AddIncrement candidate to update/remove for task '\(taskNameStr)'")
                }
            }
        }

        logger.info("Stage 2 complete. Enhancement loop finished. Final task count: \(tasksWithFinalDurations.count). Remaining time: \(remainingTime / 60, format: .fixed(precision: 1)) mins.")
        return tasksWithFinalDurations
    }

    // Stage 3: Final Ordering
    private func finalizeSchedule(
        tasksWithDurations: [NSManagedObjectID: TimeInterval], // ObjectID -> Allocated Duration
        originalOrderIDs: [NSManagedObjectID], // Preserves the original routine sequence using IDs
        taskMap: [NSManagedObjectID: CDTask] // Map to get task objects
    ) -> [ScheduledTask] {
        logger.debug("Performing Stage 3: Final Ordering...")

        var finalSchedule: [ScheduledTask] = []

        // Iterate through the original task order IDs
        for taskID in originalOrderIDs {
            // If the task was selected and has an allocated duration
            if let allocatedDuration = tasksWithDurations[taskID] {
                // Fetch the task object using the ID
                guard let task = taskMap[taskID] else {
                    logger.error("Task with ID \(taskID) scheduled but not found in map during Stage 3. Skipping.")
                    continue
                }
                let scheduled = ScheduledTask(task: task, allocatedDuration: allocatedDuration)
                finalSchedule.append(scheduled)
                logger.trace("- Added to final schedule: '\(task.taskName ?? "Unnamed")' (Order preserved), Duration: \(allocatedDuration / 60, format: .fixed(precision: 1))m")
            }
            // Tasks from originalOrderIDs not present in tasksWithDurations were filtered out
        }

        if finalSchedule.isEmpty && !originalOrderIDs.isEmpty {
            logger.warning("Final schedule is empty despite having tasks in the routine. Check available time and eligibility.")
        }

        logger.debug("Stage 3 complete. Final schedule has \(finalSchedule.count) tasks ordered correctly.")
        return finalSchedule
    }

    // --- Helper Functions ---

    /// Checks if a task is eligible for scheduling based on its last completion time and repetition interval.
    /// Takes into account daily reset for repetitionInterval == 0.
    private func isTaskEligible(task: CDTask) -> Bool {
        // Ensure the task is accessed safely, potentially re-fetching if it's a fault
        // This might involve checking task.isFault and using context.refresh(task, mergeChanges: true)
        // However, if using the taskMap correctly, tasks should already be valid objects from the context.
        // Adding a fault check just in case.

        // *** ADDED PRE-ACCESS FAULT/CONTEXT CHECK WITHIN isTaskEligible ***
        if task.isFault {
            logger.error("FAULT DETECTED in isTaskEligible for task '\(task.taskName ?? "\(task.objectID)")'. Returning false.")
            // Attempting to refresh might be risky if the object is truly gone or context invalid
            // context.refresh(task, mergeChanges: true) // Avoid refresh for now
            return false // Treat fault as ineligible immediately
        }
        if task.managedObjectContext != context {
             logger.error("CONTEXT MISMATCH DETECTED in isTaskEligible for task '\(task.taskName ?? "\(task.objectID)")'. Expected \(String(describing: context)), got \(String(describing: task.managedObjectContext)). Returning false.")
             return false // Treat context mismatch as ineligible
        }
        // *** END ADDED CHECK ***

        // Existing eligibility logic follows...
        logger.trace("Checking eligibility for task '\(task.taskName ?? "ID: \(task.objectID)")'... ")
        // Rule 1: Always eligible if never completed.
        guard let lastCompleted = task.lastCompleted else {
            logger.trace("- Eligible: Never completed.")
            return true
        }

        // Rule 2: Check for daily reset (repetitionInterval == 0)
        if task.repetitionInterval == 0 {
            let isToday = Calendar.current.isDateInToday(lastCompleted)
            logger.trace("- Daily Reset Task: Last completed \(isToday ? "today" : "before today"). Eligible: \(!isToday)")
            // Eligible only if it wasn't completed today.
            return !isToday
        }

        // Rule 3: Interval-based eligibility (repetitionInterval > 0)
        let now = Date()
        let secondsSinceCompletion = now.timeIntervalSince(lastCompleted)
        let requiredInterval = TimeInterval(task.repetitionInterval) // Assuming repetitionInterval is stored in seconds

        let isEligible = secondsSinceCompletion >= requiredInterval
        logger.trace("- Interval Task: \(String(format: "%.1f", secondsSinceCompletion))s since completion. Required: \(String(format: "%.1f", requiredInterval))s. Eligible: \(isEligible)")
        return isEligible
    }

    /// Calculates a priority score for a task.
    private func calculatePriorityScore(task: CDTask, eligible: Bool) -> Double {
        // Add fault check here too, similar to isTaskEligible
        // *** ADDED PRE-ACCESS FAULT/CONTEXT CHECK WITHIN calculatePriorityScore ***
        if task.isFault {
            logger.error("FAULT DETECTED in calculatePriorityScore for task '\(task.taskName ?? "\(task.objectID)")'. Returning lowest score.")
            return -Double.infinity
        }
        if task.managedObjectContext != context {
             logger.error("CONTEXT MISMATCH DETECTED in calculatePriorityScore for task '\(task.taskName ?? "\(task.objectID)")'. Expected \(String(describing: context)), got \(String(describing: task.managedObjectContext)). Returning lowest score.")
             return -Double.infinity
        }
        // *** END ADDED CHECK ***

        // Essential tasks don't need a score for Stage 1 prioritization, but might for Stage 2 increments.
        // Give them a very high base score if needed later.
        // For now, only non-essentials need scores for Stage 1 sorting.
        guard task.essentiality != 3 else {
            // Return a high score if needed for Stage 2, or 0 if only Stage 1 uses it.
            // Let's return a high score anticipating Stage 2 increment logic.
            return 1_000_000.0 // High score for essential tasks if needed in Stage 2
        }

        guard eligible else { return -Double.infinity } // Ensure ineligible tasks are never prioritized

        // Handle nil interval or interval <= 0: Lowest positive score
        // Use TimeInterval for intervalSeconds calculation
        guard let intervalSeconds = task.repetitionInterval > 0 ? TimeInterval(task.repetitionInterval) : nil else {
            return 0.001 // Small positive score, lower than any calculated score
        }

        // Handle nil lastCompleted: Treat as very overdue
        let lastCompleted = task.lastCompleted ?? Date.distantPast
        let timeSince = Date().timeIntervalSince(lastCompleted)

        // Score: How many intervals have passed since completion? Higher is more overdue.
        // Add 1 to avoid zero/negative scores for tasks completed exactly on/within interval but still eligible (edge case?)
        let score = max(0, (timeSince - intervalSeconds)) / intervalSeconds + 1.0

        return score
    }

    // MARK: - Schedule Estimation

    /// Estimates the duration for a given routine and essentiality level by summing the
    /// minDuration of all tasks that are currently eligible AND meet the level criteria.
    /// Uses the same eligibility check as the main scheduler.
    /// - Parameters:
    ///   - routine: The CDRoutine to estimate scheduling for.
    ///   - essentialityLevel: The maximum essentiality level to include (3=Essential, 2=Core, 1=Optional/All).
    /// - Returns: The estimated total minimum duration in seconds for eligible tasks in the tier.
    func estimateScheduleDuration(for routine: CDRoutine, includingLevel essentialityLevel: Int16) -> TimeInterval {
        logger.info("Estimating MIN duration for routine '\(routine.name ?? "Unnamed")' including level \(essentialityLevel) (ELIGIBLE ONLY)...")

        // --- Stage 0: Preparation ---
        guard let relations = routine.taskRelations as? Set<CDRoutineTask>, !relations.isEmpty else {
            logger.warning("Routine '\(routine.name ?? "Unnamed")' has no tasks for estimation.")
            return 0
        }
        let sortedRelations = relations.sorted { $0.order < $1.order }
        // Use objectIDs and fetch from context to ensure validity
        let allTaskIDs = sortedRelations.compactMap { $0.task?.objectID }

        // --- Stage 1: Filter by Eligibility & Level, Sum minDuration ---
        var totalMinDurationSum: TimeInterval = 0
        var includedTaskCount = 0

        logger.debug("Estimation: Selecting eligible tasks up to level \(essentialityLevel) using scheduler's eligibility check...")
        for taskID in allTaskIDs {
            // Fetch task safely using the scheduler's context
            guard let task = context.object(with: taskID) as? CDTask else {
                logger.warning("Task \(taskID) not found in context during estimation. Skipping.")
                continue
            }
            
            // *** ADDED PRE-ACCESS FAULT/CONTEXT CHECK WITHIN estimateScheduleDuration ***
            if task.isFault {
                logger.error("FAULT DETECTED in estimateScheduleDuration for task '\(task.taskName ?? "\(task.objectID)")'. Skipping task.")
                continue // Skip this task if it's a fault
            }
            if task.managedObjectContext != context {
                 logger.error("CONTEXT MISMATCH DETECTED in estimateScheduleDuration for task '\(task.taskName ?? "\(task.objectID)")'. Expected \(String(describing: context)), got \(String(describing: task.managedObjectContext)). Skipping task.")
                 continue // Skip this task if context is wrong
            }
            // *** END ADDED CHECK ***

            if isTaskEligible(task: task) { // Use the local function defined within this struct
                // Check if task meets the essentiality level requirement
                // Essential=3, Core=2, Optional=1. Level 3 includes only 3. Level 2 includes 3 & 2. Level 1 includes 3, 2, & 1.
                if task.essentiality >= essentialityLevel {
                    let minDurationSeconds = TimeInterval(task.minDuration * 60)
                    totalMinDurationSum += minDurationSeconds
                    includedTaskCount += 1
                    logger.trace("- Included (Lvl \(task.essentiality)): '\(task.taskName ?? "")' (MinDur: \(minDurationSeconds/60)m)")
                } else {
                    logger.trace("- Eligible but Skipped (Lvl \(task.essentiality)): '\(task.taskName ?? "")'")
                }
            } else {
                logger.trace("- Ineligible: '\(task.taskName ?? "")'")
            }
        }

        logger.info("Estimation complete for level \(essentialityLevel). \(includedTaskCount) eligible tasks included. Total MIN duration: \(totalMinDurationSum / 60, format: .fixed(precision: 1)) mins.")
        return totalMinDurationSum
    }
    
    // NOTE: There are now two different eligibility logics: `isTaskEligible` here (using lastCompleted/interval)
    // and `isEligibleNow` in the CDTask extension (using nextDueDate). This should be unified later for consistency.
    // For now, this fix makes the estimation match the scheduler's current behavior.

    // MARK: - Scheduling Stages

}

// REMOVE Duplicate definition
/*
// Add ScheduledTask struct if it's not defined elsewhere
struct ScheduledTask: Identifiable {
    let id: NSManagedObjectID // Use stable ID
    let task: CDTask // Keep reference for UI, but ensure it's used carefully
    let allocatedDuration: TimeInterval // Duration in seconds

    init(task: CDTask, allocatedDuration: TimeInterval) {
        self.id = task.objectID
        self.task = task // Assume this is used in a view that manages context correctly
        self.allocatedDuration = allocatedDuration
    }
}
*/
