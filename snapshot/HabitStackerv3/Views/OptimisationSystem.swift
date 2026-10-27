//
//  OptimisationSystem.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 08/11/2024.
//

import Foundation

// MARK: - Optimization System

class ScheduleOptimizer {
    private let logger: AppLogger
    private let currentDate: Date
    
    init(currentDate: Date = Date()) {
        self.currentDate = currentDate
        self.logger = AppLogger.create(subsystem: "com.app.ScheduleOptimizer", category: "Optimization")
    }
    
    func createOptimizedSchedule(tasks: [CDTask], availableTime: Int) throws -> [CDTask] {
        // Analyze available time
        let analysis = SchedulingAnalysis(tasks: tasks, availableTime: availableTime)
        if let warning = analysis.warningMessage {
            logger.warning(warning)
        }
        if analysis.shouldAbort {
            throw OptimizationError.insufficientTimeForEssentialTasks
        }
        
        var scheduledTasks: [CDTask] = []
        var remainingTime = analysis.effectiveAvailableTime
        
        // Schedule essential tasks first
        let essentialTasks = tasks.filter { $0.essentiality == 3 }
            .sorted { Int($0.minDuration) < Int($1.minDuration) }
        
        for task in essentialTasks {
            guard Int(task.minDuration) <= remainingTime else {
                throw OptimizationError.insufficientTimeForEssentialTasks
            }
            scheduledTasks.append(task)
            remainingTime -= Int(task.minDuration)
            logger.debug("Scheduled essential task: \(task.taskName ?? ""), Duration: \(task.minDuration)m, Remaining time: \(remainingTime)m")
        }
        
        // Calculate priority scores for remaining tasks
        let remainingTasks = tasks.filter { $0.essentiality != 3 }
        let scoredTasks = remainingTasks.map { task in
            PriorityScore(task: task, currentDate: currentDate)
        }
        
        // Log priority scores
        logger.debug("Priority scores for remaining tasks:")
        scoredTasks.forEach { score in
            logger.debug(score.description)
        }
        
        // Find optimal combination of remaining tasks
                if remainingTime > 0 {
                    let optimizer = TaskCombinationOptimizer(
                        tasks: scoredTasks.map { $0.task },
                        availableTime: remainingTime,
                        logger: logger
                    )
                    
                    if let optimalCombination = optimizer.findOptimalCombination() {
                        scheduledTasks.append(contentsOf: optimalCombination)
                        logger.info("Added \(optimalCombination.count) additional tasks to schedule")
                    } else {
                        logger.info("No additional tasks could be optimally scheduled")
                    }
                }
                
                return scheduledTasks
            }
}

// MARK: - Task Combination Optimizer
class TaskCombinationOptimizer {
    private let tasks: [CDTask]
    private let availableTime: Int
    private let logger: AppLogger
    
    init(tasks: [CDTask], availableTime: Int, logger: AppLogger) {
        self.tasks = tasks
        self.availableTime = availableTime
        self.logger = logger
    }
    
    
    func findOptimalCombination() -> [CDTask]? {  // Changed return type to optional
        var bestCombination: [CDTask] = []
        var bestScore = 0.0
        var bestTimeUtilization = 0
        
        // Try different combination sizes
        for size in (1...tasks.count).reversed() {
            generateCombinations(size: size) { combination in
                let totalTime = combination.reduce(0) { $0 + Int($1.minDuration) }
                if totalTime <= availableTime {
                    let score = calculateCombinationScore(combination)
                    if score > bestScore || (score == bestScore && totalTime > bestTimeUtilization) {
                        bestScore = score
                        bestCombination = combination
                        bestTimeUtilization = totalTime
                        
                        logger.debug("""
                            Found better combination:
                            - Tasks: \(combination.map { $0.taskName ?? "" })
                            - Total time: \(totalTime)m
                            - Score: \(score)
                            """)
                    }
                }
                return true
            }
            
            // If we found a good combination, stop looking
            if !bestCombination.isEmpty &&
               Double(bestTimeUtilization) / Double(availableTime) >= 0.8 {
                break
            }
        }
        
        return bestCombination.isEmpty ? nil : bestCombination  // Return nil if no combination found
    }
    
    private func generateCombinations(size: Int, process: ([CDTask]) -> Bool) {
        var stack: [(combination: [CDTask], nextIndex: Int)] = [([], 0)]
        
        while let current = stack.popLast() {
            if current.combination.count == size {
                if !process(current.combination) {
                    return
                }
                continue
            }
            
            for i in (current.nextIndex..<tasks.count).reversed() {
                stack.append((current.combination + [tasks[i]], i + 1))
            }
        }
    }
    
    private func calculateCombinationScore(_ combination: [CDTask]) -> Double {
        combination.reduce(0.0) { total, task in
            total + PriorityScore(task: task, currentDate: Date()).score
        }
    }
}
