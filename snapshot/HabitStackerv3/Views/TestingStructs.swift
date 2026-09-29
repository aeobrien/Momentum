//
//  TestingStructs.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 08/11/2024.
//

import Foundation

enum OptimizationError: Error {
    case insufficientTimeForEssentialTasks
    case invalidTaskConfiguration
    case optimizationFailed
    
    var description: String {
        switch self {
        case .insufficientTimeForEssentialTasks:
            return "Not enough time to schedule essential tasks"
        case .invalidTaskConfiguration:
            return "Invalid task configuration detected"
        case .optimizationFailed:
            return "Failed to find optimal schedule"
        }
    }
}

struct SchedulingAnalysis {
    let totalEssentialTime: Int
    let availableTime: Int
    let bufferTime: Int = 10
    let effectiveAvailableTime: Int
    let warningMessage: String?
    let shouldAbort: Bool
    
    init(tasks: [CDTask], availableTime: Int) {
        self.availableTime = availableTime
        self.effectiveAvailableTime = availableTime - bufferTime
        
        let essentialTasks = tasks.filter { $0.essentiality == 3 }
        self.totalEssentialTime = essentialTasks.reduce(0) { $0 + Int($1.minDuration) }
        
        if totalEssentialTime > effectiveAvailableTime {
            self.warningMessage = """
                Warning: Essential tasks require \(totalEssentialTime) minutes, but only \(effectiveAvailableTime) minutes available
                (including \(bufferTime) minute buffer).
                Essential tasks:
                \(essentialTasks.map { "- \($0.taskName ?? ""): \($0.minDuration) minutes" }.joined(separator: "\n"))
                """
            self.shouldAbort = true
        } else if totalEssentialTime > (effectiveAvailableTime / 2) {
            self.warningMessage = """
                Note: Essential tasks consume \(totalEssentialTime) of \(effectiveAvailableTime) available minutes,
                leaving only \(effectiveAvailableTime - totalEssentialTime) minutes for other tasks.
                """
            self.shouldAbort = false
        } else {
            self.warningMessage = nil
            self.shouldAbort = false
        }
    }
}

struct PriorityScore: CustomStringConvertible {
    let score: Double
    let task: CDTask
    let factors: [String: Double]
    
    var description: String {
        """
        Priority Score for \(task.taskName ?? "Unknown"):
        - Base Priority: \(factors["basePriority"] ?? 0)
        - Never Completed Boost: \(factors["neverCompletedBoost"] ?? 0)
        - Overdue Factor: \(factors["overdueFactor"] ?? 1)
        - Final Score: \(score)
        """
    }
    
    init(task: CDTask, currentDate: Date) {
        var factors: [String: Double] = [:]
        
        let basePriority: Double = switch task.essentiality {
            case 3: 1000  // Essential
            case 2: 100   // Core
            case 1: 10    // Non-essential
            default: 0
        }
        factors["basePriority"] = basePriority
        
        let neverCompletedBoost: Double
        if task.lastCompleted == nil {
            neverCompletedBoost = basePriority * 0.5
            factors["neverCompletedBoost"] = neverCompletedBoost
        } else {
            neverCompletedBoost = 0
            factors["neverCompletedBoost"] = 0
        }
        
        let overdueFactor: Double
        if let lastCompleted = task.lastCompleted,
           task.repetitionInterval > 0 {
            let timeSinceCompletion = currentDate.timeIntervalSince(lastCompleted)
            let repetitionInterval = Double(task.repetitionInterval)
            let overdueRatio = timeSinceCompletion / repetitionInterval
            overdueFactor = pow(overdueRatio, 1.5)
            factors["overdueFactor"] = overdueFactor
        } else {
            overdueFactor = 1
            factors["overdueFactor"] = 1
        }
        
        self.score = (basePriority + neverCompletedBoost) * overdueFactor
        self.task = task
        self.factors = factors
    }
}

struct TaskCombination {
    let tasks: [CDTask]
    let totalTime: Int
    let totalScore: Double
    
    var averageScore: Double {
        Double(totalScore) / Double(tasks.count)
    }
}
