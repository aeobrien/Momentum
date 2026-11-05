//
//  VariableDurationTaskScheduling.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 08/11/2024.
//

import Foundation

// First, structures to handle variable duration tasks
struct ExtendableDuration {
    let minDuration: Int
    let maxDuration: Int
    let preferredDuration: Int
    var currentDuration: Int
    
    init(minDuration: Int, maxDuration: Int) {
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.preferredDuration = minDuration + (maxDuration - minDuration) / 2
        self.currentDuration = minDuration
    }
    
    var canExtend: Bool {
        currentDuration < maxDuration
    }
    
    var isAtPreferred: Bool {
        currentDuration >= preferredDuration
    }
    
    mutating func extend(by minutes: Int) -> Bool {
        guard canExtend else { return false }
        let newDuration = min(currentDuration + minutes, maxDuration)
        let extensionAmount = newDuration - currentDuration
        if extensionAmount > 0 {
            currentDuration = newDuration
            return true
        }
        return false
    }
}

struct PrioritizedTask {
    let task: CDTask
    var duration: ExtendableDuration?
    let originalIndex: Int
    var priorityScore: Double
    
    var isVariable: Bool {
        duration != nil
    }
    
    // Calculate priority score for extending duration
    func extensionPriorityScore(contextualSpread: ClosedRange<Double>) -> Double {
        guard let duration = duration,
              duration.canExtend else { return 0 }
        
        let baseScore = task.essentiality == 3 ? 1000.0 :
                       task.essentiality == 2 ? 100.0 : 10.0
        
        // Calculate progress toward preferred
        let totalRange = duration.maxDuration - duration.minDuration
        let currentProgress = duration.currentDuration - duration.minDuration
        let toPreferred = duration.preferredDuration - duration.minDuration
        
        let progressFactor: Double
        if currentProgress >= toPreferred {
            // Steeper decay after preferred
            let remainingRange = duration.maxDuration - duration.preferredDuration
            let remaining = duration.maxDuration - duration.currentDuration
            progressFactor = remainingRange > 0 ? Double(remaining) / Double(remainingRange) : 0.0
        } else {
            // Gentler decay up to preferred
            progressFactor = toPreferred > 0 ? Double(currentProgress) / Double(toPreferred) : 1.0
        }
        
        // Adjust score based on progress
        let adjustedScore = baseScore * progressFactor
        
        // Scale the score to fit within the context of other tasks
        let spreadRange = contextualSpread.upperBound - contextualSpread.lowerBound
        let scaledScore = contextualSpread.lowerBound + (adjustedScore / baseScore) * spreadRange
        
        return scaledScore
    }
}

class VariableDurationScheduler {
    private let logger = AppLogger.create(subsystem: "com.app.Scheduler", category: "VariableDuration")
    private let settingsManager = SettingsManager.shared
    
    func schedule(tasks: [CDTask], availableTime: Int) -> (scheduled: [CDTask], durations: [String: Int]) {
        let requirements = calculateTimeRequirements(tasks: tasks, availableTime: availableTime)
        let bufferMinutes = settingsManager.scheduleBufferMinutes
        if Int(requirements.essentialTime/60) > availableTime - bufferMinutes {
            logger.error("""
                Cannot schedule essential tasks:
                Required: \(Int(requirements.essentialTime/60))m
                Available after buffer: \(availableTime - bufferMinutes)m
                """)
            return ([], [:])
        }

        var remainingTime = availableTime - bufferMinutes  // Buffer
        var scheduledTasks: [PrioritizedTask] = []
        var durationMap: [String: Int] = [:]
        
        logger.info("""
            Starting schedule:
            Essential: \(Int(requirements.essentialTime/60))m
            Core: \(Int(requirements.coreTime/60))m
            Available: \(availableTime)m (\(remainingTime)m after buffer)
            """)
        
        let prioritizedTasks = createPrioritizedTasks(from: tasks)
        let (essential, core, optional) = categorizeAndSort(tasks: prioritizedTasks)
        
        guard scheduleInitialTasks(essential, &scheduledTasks, &remainingTime, &durationMap) else {
            return ([], [:])
        }
        
        scheduleInitialTasks(core, &scheduledTasks, &remainingTime, &durationMap)
        
        var remainingOptional = optional
        var extensibleTasks = scheduledTasks.filter { $0.isVariable && $0.duration?.canExtend == true }
        
        while remainingTime >= 5 && (!remainingOptional.isEmpty || !extensibleTasks.isEmpty) {
            let contextualSpread = calculatePrioritySpread(optional: remainingOptional, extensible: extensibleTasks)
            let nextAction = determineNextAction(
                optional: remainingOptional,
                extensible: extensibleTasks,
                contextualSpread: contextualSpread,
                remainingTime: remainingTime
            )
            
            switch nextAction {
            case .scheduleTask(let task):
                if let taskId = task.task.uuid?.uuidString {
                    let duration = task.duration?.currentDuration ?? Int(task.task.minDuration)
                    
                    if duration <= remainingTime {
                        durationMap[taskId] = duration
                        scheduledTasks.append(task)
                        remainingTime -= duration
                        remainingOptional.removeAll { $0.task.uuid == task.task.uuid }
                        logger.debug("Added optional: \(task.task.taskName ?? "") (E\(task.task.essentiality)): \(duration)m")
                        
                        if task.isVariable && task.duration?.canExtend == true {
                            extensibleTasks.append(task)
                        }
                    } else {
                        remainingOptional.removeAll { $0.task.uuid == task.task.uuid }
                    }
                }
                
            case .extendTask(let task):
                if let index = scheduledTasks.firstIndex(where: { $0.task.uuid == task.task.uuid }),
                   let taskId = task.task.uuid?.uuidString {
                    let oldDuration = scheduledTasks[index].duration?.currentDuration ?? Int(task.task.minDuration)
                    if scheduledTasks[index].duration?.extend(by: 5) == true {
                        let newDuration = scheduledTasks[index].duration?.currentDuration ?? Int(task.task.minDuration)
                        durationMap[taskId] = newDuration
                        remainingTime -= 5
                        logger.debug("Extended \(task.task.taskName ?? ""): \(oldDuration)m -> \(newDuration)m")
                        extensibleTasks = scheduledTasks.filter { $0.isVariable && $0.duration?.canExtend == true }
                    }
                }
                
            case .none:
                break
            }
        }
        
        let sortedTasks = scheduledTasks.sorted { $0.originalIndex < $1.originalIndex }
        logSchedulingResults(original: tasks, scheduled: sortedTasks, durations: durationMap)
        return (sortedTasks.map { $0.task }, durationMap)
    }
    
    private func preCheckScheduling(tasks: [CDTask], availableTime: Int) -> PreCheckResult {
        let requirements = calculateTimeRequirements(tasks: tasks, availableTime: availableTime)
        let essentialTasks = tasks.filter { $0.essentiality == 3 }
        
        // Early validation of essential tasks
        guard requirements.canScheduleEssentialTasks else {
            let shortfall = requirements.essentialTime - requirements.effectiveAvailableTime
            return .essentialTasksWontFit(shortfall: Int(shortfall / 60))
        }
        
        // Just need to verify total essential task time fits within available time
        let totalEssentialTime = essentialTasks.reduce(0) { $0 + Int($1.minDuration) }
        let bufferMinutes = settingsManager.scheduleBufferMinutes
        if totalEssentialTime > (availableTime - bufferMinutes) {
            return .essentialTasksWontFit(shortfall: totalEssentialTime - (availableTime - bufferMinutes))
        }
        
        return .success(requirements)
    }

    // Helper methods...
    private func createPrioritizedTasks(from tasks: [CDTask]) -> [PrioritizedTask] {
        return tasks.enumerated().map { index, task in
            let duration = task.minDuration != task.maxDuration ?
                ExtendableDuration(minDuration: Int(task.minDuration),
                                 maxDuration: Int(task.maxDuration)) : nil
            
            return PrioritizedTask(
                task: task,
                duration: duration,
                originalIndex: index,
                priorityScore: calculateBaseScore(for: task)
            )
        }
    }
    
    private func calculateBaseScore(for task: CDTask) -> Double {
        let baseScore = task.essentiality == 3 ? 1000.0 :
                       task.essentiality == 2 ? 100.0 : 10.0
        
        let neverCompletedBoost = task.lastCompleted == nil ? baseScore * 0.5 : 0.0
        
        var overdueFactor = 1.0
        if let lastCompleted = task.lastCompleted,
           task.repetitionInterval > 0 {
            let timeSince = Date().timeIntervalSince(lastCompleted)
            let interval = Double(task.repetitionInterval)
            overdueFactor = pow(timeSince / interval, 1.5)
        }
        
        let finalScore = (baseScore + neverCompletedBoost) * overdueFactor
        
        // Single line log per score calculation
        logger.debug("""
            Score: \(task.taskName ?? ""): \(String(format: "%.1f", finalScore)) \
            (E\(task.essentiality), \(task.lastCompleted == nil ? "Never completed" : "Completed"))
            """)
        
        return finalScore
    }
    
    // Additional helper methods to be implemented...
}

// Enums for scheduling decisions
enum SchedulingAction {
    case scheduleTask(PrioritizedTask)
    case extendTask(PrioritizedTask)
    case none
}

extension VariableDurationScheduler {
    private func categorizeAndSort(tasks: [PrioritizedTask]) -> (
        essential: [PrioritizedTask],
        core: [PrioritizedTask],
        optional: [PrioritizedTask]
    ) {
        let essential = tasks.filter { $0.task.essentiality == 3 }
        let core = tasks.filter { $0.task.essentiality == 2 }
        let optional = tasks.filter { $0.task.essentiality == 1 }
        
        logger.info("""
            Tasks categorized:
            Essential: \(essential.count)
            Core: \(core.count)
            Optional: \(optional.count)
            """)
        
        return (essential, core, optional)
    }
    
    private func scheduleInitialTasks(
            _ tasks: [PrioritizedTask],
            _ scheduledTasks: inout [PrioritizedTask],
            _ remainingTime: inout Int,
            _ durationMap: inout [String: Int]
        ) -> Bool {
            var runningTotal = 0
            let isEssential = tasks.first?.task.essentiality == 3
            
            for task in tasks {
                let duration = task.duration?.currentDuration ?? Int(task.task.minDuration)
                let wouldExceedTime = duration > remainingTime
                
                if wouldExceedTime {
                    if isEssential {
                        logger.error("""
                            Essential task scheduling failed:
                            Task: \(task.task.taskName ?? "")
                            Duration: \(duration)m
                            Remaining: \(remainingTime - runningTotal)m
                            Already scheduled: \(runningTotal)m
                            """)
                        return false
                    }
                    logger.debug("Skipping non-essential: \(task.task.taskName ?? "") (\(duration)m exceeds \(remainingTime - runningTotal)m)")
                    continue
                }
                
                if let taskId = task.task.uuid?.uuidString {
                    durationMap[taskId] = duration
                }
                scheduledTasks.append(task)
                remainingTime -= duration
                runningTotal += duration
            }
            
            let taskType = isEssential ? "essential" : "core"
            logger.info("Scheduled \(taskType) tasks: \(runningTotal)m total")
            return true
        }
       
    private func calculateTimeRequirements(tasks: [CDTask], availableTime: Int) -> TimeRequirements {
        let essentialTime = tasks.filter { $0.essentiality == 3 }
            .reduce(0, { sum, task in sum + Int(task.minDuration) })
        let coreTime = tasks.filter { $0.essentiality == 2 }
            .reduce(0, { sum, task in sum + Int(task.minDuration) })
            
        logger.info("""
            Time requirements:
            Essential: \(essentialTime)m
            Core: \(coreTime)m
            Total minimum: \(essentialTime + coreTime)m
            Available: \(availableTime)m
            """)
            
        return TimeRequirements(
            essentialTime: TimeInterval(essentialTime * 60),
            coreTime: TimeInterval(coreTime * 60),
            totalAvailableTime: TimeInterval(availableTime * 60)
        )
    }
    
    private func calculatePrioritySpread(
        optional: [PrioritizedTask],
        extensible: [PrioritizedTask]
    ) -> ClosedRange<Double> {
        let allScores = optional.map { $0.priorityScore } +
            extensible.compactMap { $0.duration?.canExtend == true ? $0.priorityScore : nil }
        
        guard !allScores.isEmpty else { return 0.0...0.0 }
        
        let min = allScores.min() ?? 0.0
        let max = allScores.max() ?? 0.0
        
        logger.debug("Priority spread: \(min)...\(max)")
        
        return min...max
    }
    
    private func determineNextAction(
        optional: [PrioritizedTask],
        extensible: [PrioritizedTask],
        contextualSpread: ClosedRange<Double>,
        remainingTime: Int
    ) -> SchedulingAction {
        var highestScore = -Double.infinity
        var selectedAction: SchedulingAction = .none

        // Check optional tasks
        for task in optional {
            let duration = Int(task.task.minDuration)
            if duration <= remainingTime {
                if task.priorityScore > highestScore {
                    highestScore = task.priorityScore
                    selectedAction = .scheduleTask(task)
                }
            }
        }

        // Check extensible tasks
        for task in extensible {
            let extensionScore = task.extensionPriorityScore(contextualSpread: contextualSpread)
            if extensionScore > highestScore && remainingTime >= 5 {
                highestScore = extensionScore
                selectedAction = .extendTask(task)
            }
        }

        switch selectedAction {
        case .scheduleTask(let task):
            logger.debug("Decision: Schedule \(task.task.taskName ?? "") (score: \(String(format: "%.1f", highestScore)))")
        case .extendTask(let task):
            logger.debug("Decision: Extend \(task.task.taskName ?? "") (score: \(String(format: "%.1f", highestScore)))")
        case .none:
            logger.debug("Decision: No action possible with \(remainingTime)m left")
        }

        return selectedAction
    }
    
    private func logSchedulingResults(
        original: [CDTask],
        scheduled: [PrioritizedTask],
        durations: [String: Int]
    ) {
        let totalTime = durations.values.reduce(0, +)
        let essentialCount = scheduled.filter { $0.task.essentiality == 3 }.count
        let originalEssentialCount = original.filter { $0.essentiality == 3 }.count
        let coreCount = scheduled.filter { $0.task.essentiality == 2 }.count
        let originalCoreCount = original.filter { $0.essentiality == 2 }.count
        let optionalCount = scheduled.filter { $0.task.essentiality == 1 }.count
        let extendedCount = scheduled.filter {
            $0.duration?.currentDuration ?? 0 > Int($0.task.minDuration)
        }.count

        logger.info("""
            Final Schedule:
            Tasks scheduled: \(scheduled.count)/\(original.count)
            Time used: \(totalTime)m/105m
            Essential tasks: \(essentialCount)/\(originalEssentialCount) complete
            Core tasks: \(coreCount)/\(originalCoreCount) complete
            Optional tasks: \(optionalCount) scheduled, \(extendedCount) extended
            """)
    }
}

enum PreCheckResult {
    case success(TimeRequirements)
    case essentialTasksWontFit(shortfall: Int)
}
