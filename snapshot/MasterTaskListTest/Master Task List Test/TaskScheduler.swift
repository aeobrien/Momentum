import Foundation

struct TaskScheduler {
    
    var currentTime: Date
    
    func scheduleTasks(filteredTasks: [CustomTask], availableTime: TimeInterval) -> [(task: CustomTask, duration: Int)] {
        var scheduledTasks: [(task: CustomTask, duration: Int)] = []
        var totalScheduledTime: TimeInterval = 0
        var alternateToggle = true
        var extendedTaskUUIDs: Set<String> = []
        var remainingNonEssentialTasks: [CustomTask] = []
        var remainingFlexibleTasks: [CustomTask] = []
        var flexibleTasks: [CustomTask] = []
        var priorityScores: [String: Double] = [:]
        
        // Schedule essential tasks
        scheduleEssentialTasks(
            filteredTasks: filteredTasks,
            availableTime: availableTime,
            scheduledTasks: &scheduledTasks,
            totalScheduledTime: &totalScheduledTime,
            flexibleTasks: &flexibleTasks
        )
        print("Flexible tasks after scheduling essential tasks: \(flexibleTasks.count)")
        
        // Schedule core tasks
        scheduleCoreTasks(
            filteredTasks: filteredTasks,
            availableTime: availableTime,
            scheduledTasks: &scheduledTasks,
            totalScheduledTime: &totalScheduledTime,
            flexibleTasks: &flexibleTasks
        )
        print("Flexible tasks after scheduling core tasks: \(flexibleTasks.count)")
        
        // Identify flexible tasks after essential and core tasks are scheduled
        identifyFlexibleTasks(scheduledTasks: scheduledTasks, flexibleTasks: &flexibleTasks)
        print("Flexible tasks after identification: \(flexibleTasks.count)")
        
        // Identify non-essential tasks, assign priority scores, and identify flexible tasks
        (remainingNonEssentialTasks, remainingFlexibleTasks) = identifyAndPrioritizeTasks(
            filteredTasks: filteredTasks,
            scheduledTasks: scheduledTasks,
            priorityScores: &priorityScores,
            flexibleTasks: &flexibleTasks  // Pass as inout
        )
        print("Remaining flexible tasks after prioritization: \(remainingFlexibleTasks.count)")
        
        // Schedule flexible and non-essential tasks
        scheduleFlexibleAndNonEssentialTasks(
            nonEssentialTasks: &remainingNonEssentialTasks,
            flexibleTasks: &remainingFlexibleTasks,
            availableTime: availableTime,
            scheduledTasks: &scheduledTasks,
            totalScheduledTime: &totalScheduledTime,
            alternateToggle: &alternateToggle,
            extendedTaskUUIDs: &extendedTaskUUIDs,
            priorityScores: priorityScores
        )
        print("Final flexible tasks count: \(remainingFlexibleTasks.count)")
        
        return scheduledTasks
    }
    
    private func identifyFlexibleTasks(scheduledTasks: [(task: CustomTask, duration: Int)], flexibleTasks: inout [CustomTask]) {
        print("Starting flexible task identification...")
        
        for scheduledTask in scheduledTasks {
            let task = scheduledTask.task
            let minDuration = task.minDuration
            let maxDuration = task.maxDuration
            
            print("Checking task: \(task.taskName)")
            print(" - minDuration: \(minDuration) seconds")
            print(" - maxDuration: \(maxDuration) seconds")
            
            if minDuration < maxDuration {
                if !flexibleTasks.contains(where: { $0.UUID == task.UUID }) {
                    flexibleTasks.append(task)
                    print(" - Task is flexible. Added \(task.taskName) to flexibleTasks.")
                } else {
                    print(" - Task \(task.taskName) is already in flexibleTasks.")
                }
            } else {
                print(" - Task is not flexible.")
            }
        }
        
        print("Flexible task identification completed. Total flexible tasks identified: \(flexibleTasks.count)")
    }
    
    private func scheduleEssentialTasks(filteredTasks: [CustomTask], availableTime: TimeInterval, scheduledTasks: inout [(task: CustomTask, duration: Int)], totalScheduledTime: inout TimeInterval, flexibleTasks: inout [CustomTask]) {
        for task in filteredTasks where task.essentiality == 3 {
            let taskDuration = task.minDuration
            if totalScheduledTime + TimeInterval(taskDuration) <= availableTime {
                scheduledTasks.append((task: task, duration: taskDuration))
                totalScheduledTime += TimeInterval(taskDuration)
                
                // Debugging: Print lastCompleted when scheduling the task
                print("Scheduled Essential Task: \(task.taskName)")
                print(" - Last Completed: \(task.lastCompleted ?? "N/A")")
                
                // Check if the task is flexible and add it to flexibleTasks
                if task.minDuration < task.maxDuration {
                    flexibleTasks.append(task)
                }
            }
        }
    }
    
    private func scheduleCoreTasks(filteredTasks: [CustomTask], availableTime: TimeInterval, scheduledTasks: inout [(task: CustomTask, duration: Int)], totalScheduledTime: inout TimeInterval, flexibleTasks: inout [CustomTask]) {
        for task in filteredTasks where task.essentiality == 2 {
            let taskDuration = task.minDuration
            if totalScheduledTime + TimeInterval(taskDuration) <= availableTime {
                scheduledTasks.append((task: task, duration: taskDuration))
                totalScheduledTime += TimeInterval(taskDuration)
                
                // Debugging: Print lastCompleted when scheduling the task
                print("Scheduled Core Task: \(task.taskName)")
                print(" - Last Completed: \(task.lastCompleted ?? "N/A")")
                
                // Check if the task is flexible and add it to flexibleTasks
                if task.minDuration < task.maxDuration {
                    flexibleTasks.append(task)
                }
            }
        }
    }
    
    private func scheduleFlexibleAndNonEssentialTasks(
        nonEssentialTasks: inout [CustomTask],
        flexibleTasks: inout [CustomTask],
        availableTime: TimeInterval,
        scheduledTasks: inout [(task: CustomTask, duration: Int)],
        totalScheduledTime: inout TimeInterval,
        alternateToggle: inout Bool,
        extendedTaskUUIDs: inout Set<String>,
        priorityScores: [String: Double]
    ) {
        var unschedulableTaskUUIDs: Set<String> = []
        var nonEssentialFailure = false
        var flexibleFailure = false
        
        while totalScheduledTime < availableTime {
            print("Loop Start - Total Scheduled Time: \(totalScheduledTime / 60) minutes, Available Time: \(availableTime / 60) minutes")
            print("Remaining Non-Essential Tasks: \(nonEssentialTasks.count)")
            print("Remaining Flexible Tasks: \(flexibleTasks.count)")
            
            var taskScheduledOrExtended = false
            
            // Schedule the highest priority non-essential task
            if !nonEssentialTasks.isEmpty && !nonEssentialFailure {
                if let taskToSchedule = nonEssentialTasks.max(by: { priorityScores[$0.UUID] ?? 0 < priorityScores[$1.UUID] ?? 0 }), !unschedulableTaskUUIDs.contains(taskToSchedule.UUID) {
                    let taskDuration = taskToSchedule.minDuration
                    print("Attempting to schedule non-essential task: \(taskToSchedule.taskName) with duration \(taskDuration / 60) minutes and priority \(priorityScores[taskToSchedule.UUID] ?? 0.0)")
                    
                    if totalScheduledTime + TimeInterval(taskDuration) <= availableTime {
                        scheduledTasks.append((task: taskToSchedule, duration: taskDuration))
                        totalScheduledTime += TimeInterval(taskDuration)
                        nonEssentialTasks.removeAll { $0.UUID == taskToSchedule.UUID }
                        taskScheduledOrExtended = true
                        print("Scheduled Non-Essential Task: \(taskToSchedule.taskName)")
                        print(" - Last Completed: \(taskToSchedule.lastCompleted ?? "N/A")")
                        
                        // Check if the newly scheduled task is flexible and add it to flexibleTasks
                        if taskToSchedule.minDuration < taskToSchedule.maxDuration {
                            if !flexibleTasks.contains(where: { $0.UUID == taskToSchedule.UUID }) {
                                flexibleTasks.append(taskToSchedule)
                                print("Newly scheduled task \(taskToSchedule.taskName) identified as flexible.")
                            }
                        }
                        
                    } else {
                        print("Cannot schedule \(taskToSchedule.taskName) due to time constraints.")
                        unschedulableTaskUUIDs.insert(taskToSchedule.UUID)
                    }
                } else {
                    nonEssentialFailure = true
                }
            } else {
                nonEssentialFailure = true
            }
            
            // Extend flexible tasks
            if !flexibleFailure {
                if extendFlexibleTasks(flexibleTasks: &flexibleTasks, availableTime: availableTime, scheduledTasks: &scheduledTasks, totalScheduledTime: &totalScheduledTime, extendedTaskUUIDs: &extendedTaskUUIDs) {
                    taskScheduledOrExtended = true
                } else {
                    flexibleFailure = true
                }
            } else {
                flexibleFailure = true
            }
            
            if nonEssentialFailure && flexibleFailure {
                print("Both non-essential and flexible tasks failed to schedule. Exiting loop.")
                break
            }
            
            if !taskScheduledOrExtended {
                print("No more tasks to schedule or extend. Exiting loop.")
                break
            }
            
            alternateToggle.toggle()
            print("Loop End - Total Scheduled Time: \(totalScheduledTime / 60) minutes")
            print("----------------------------------------------------")
        }
        
        print("Final scheduled tasks:")
        for task in scheduledTasks {
            print("Task: \(task.task.taskName), Duration: \(task.duration / 60) minutes, Min Duration: \(task.task.minDuration), Max Duration: \(task.task.maxDuration)")
        }
    }
    private func identifyAndPrioritizeTasks(
        filteredTasks: [CustomTask],
        scheduledTasks: [(task: CustomTask, duration: Int)],
        priorityScores: inout [String: Double],
        flexibleTasks: inout [CustomTask]  // Pass flexibleTasks as inout parameter
    ) -> ([CustomTask], [CustomTask]) {
        var nonEssentialTasks: [CustomTask] = []
        
        for task in filteredTasks where !scheduledTasks.contains(where: { $0.task.UUID == task.UUID }) {
            var priorityScore = 1.0
            
            if task.lastCompleted == nil {
                priorityScore += 0.1
            }
            
            if task.essentiality == 1 {
                // Non-essential task logic
                if let lastCompletedString = task.lastCompleted,
                   let lastCompletedDate = lastCompletedString.toDate(),
                   let repetitionInterval = task.repetitionInterval, repetitionInterval > 0 {
                    
                    let repetitionDeadline = lastCompletedDate.addingTimeInterval(TimeInterval(repetitionInterval))
                    let daysSinceRepetitionDeadline = max(0, currentTime.timeIntervalSince(repetitionDeadline) / 86400) // 86400 = seconds in a day
                    
                    if daysSinceRepetitionDeadline >= 1 {
                        priorityScore += 0.1 * daysSinceRepetitionDeadline
                    }
                }
                
                nonEssentialTasks.append(task)
            }
            
            // Flexible task logic
            if task.minDuration < task.maxDuration {
                // Add the task to flexibleTasks only if it has been scheduled already
                if scheduledTasks.contains(where: { $0.task.UUID == task.UUID }) {
                    if !flexibleTasks.contains(where: { $0.UUID == task.UUID }) { // Avoid duplication
                        flexibleTasks.append(task)
                    }
                }
            }
            
            priorityScores[task.UUID] = priorityScore  // Store priority score using UUID (String) as key
            print("Task: \(task.taskName), Priority Score: \(priorityScore)")
        }
        
        print("Flexible Tasks Identified: \(flexibleTasks.count)" )
        return (nonEssentialTasks, flexibleTasks)
    }
    
    private func extendFlexibleTasks(
        flexibleTasks: inout [CustomTask],
        availableTime: TimeInterval,
        scheduledTasks: inout [(task: CustomTask, duration: Int)],
        totalScheduledTime: inout TimeInterval,
        extendedTaskUUIDs: inout Set<String>
    ) -> Bool {
        var taskExtended = false
        print("Attempting to extend flexible tasks. Current flexible tasks count: \(flexibleTasks.count)")
        
        for taskToExtend in flexibleTasks {
            let currentDuration = scheduledTasks.first(where: { $0.task.UUID == taskToExtend.UUID })?.duration ?? 0
            let additionalTime = 300 // 5 minutes in seconds
            
            print("Attempting to extend task: \(taskToExtend.taskName)")
            print("Current Duration: \(currentDuration) seconds")
            print("Min Duration: \(taskToExtend.minDuration) seconds")
            print("Max Duration: \(taskToExtend.maxDuration) seconds")
            
            if Double(currentDuration + additionalTime) <= Double(taskToExtend.maxDuration) &&
                totalScheduledTime + Double(additionalTime) <= availableTime {
                if let index = scheduledTasks.firstIndex(where: { $0.task.UUID == taskToExtend.UUID }) {
                    scheduledTasks[index].duration += additionalTime
                } else {
                    scheduledTasks.append((task: taskToExtend, duration: additionalTime))
                }
                
                totalScheduledTime += Double(additionalTime)
                extendedTaskUUIDs.insert(taskToExtend.UUID)
                taskExtended = true
                print("Extended flexible task: \(taskToExtend.taskName) by \(additionalTime / 60) minutes")
            } else {
                print("Cannot extend \(taskToExtend.taskName) further due to time or max duration constraints.")
            }
        }
        
        if !taskExtended {
            print("No flexible tasks were extended.")
        }
        
        return taskExtended
    }
    
    private func extendFlexibleTask(taskToExtend: CustomTask, scheduledTasks: inout [(task: CustomTask, duration: Int)]) -> (task: CustomTask, duration: Int)? {
        if let existingTaskIndex = scheduledTasks.firstIndex(where: { $0.task.UUID == taskToExtend.UUID }) {
            let currentDuration = scheduledTasks[existingTaskIndex].duration
            let maxPossibleExtension = taskToExtend.maxDuration - currentDuration
            let extensionTime = min(maxPossibleExtension, 300) // Extend by up to 5 minutes
            
            if extensionTime > 0 {
                scheduledTasks[existingTaskIndex].duration += extensionTime
                return (taskToExtend, extensionTime)
            }
        }
        return nil
    }
    
}
