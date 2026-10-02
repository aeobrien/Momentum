//
//  ScheduleStructs.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 23/10/2024.
//

import Foundation
import CoreData

/// Represents the current scheduling state including selected routine and end time
struct SchedulingState {
    let selectedRoutine: Routine
    let endTime: Date
    var availableTime: TimeInterval
    var scheduledTasks: [ScheduledTask]
}

/// Represents a task that has been scheduled with allocated duration.
struct ScheduledTask: Identifiable, Hashable {
    let id: NSManagedObjectID
    let task: CDTask
    var allocatedDuration: TimeInterval
    
    init(task: CDTask, allocatedDuration: TimeInterval) {
        self.id = task.objectID
        self.task = task
        self.allocatedDuration = allocatedDuration
    }

    static func == (lhs: ScheduledTask, rhs: ScheduledTask) -> Bool {
        lhs.task.objectID == rhs.task.objectID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(task.objectID)
    }
}

/// Represents the time requirements for scheduling
struct TimeRequirements {
    let essentialTime: TimeInterval
    let coreTime: TimeInterval
    let totalAvailableTime: TimeInterval
    let standardBuffer: TimeInterval = 15 * 60  // 15 minutes in seconds
    
    // Flexible buffer handling
    var minimumBuffer: TimeInterval { standardBuffer / 3 }  // 5 minutes minimum
    
    var effectiveBuffer: TimeInterval {
        // If essential tasks barely don't fit with standard buffer, reduce buffer
        if essentialTime > (totalAvailableTime - standardBuffer) &&
           essentialTime <= (totalAvailableTime - minimumBuffer) {
            return totalAvailableTime - essentialTime
        }
        return standardBuffer
    }
    
    var canScheduleEssentialTasks: Bool {
        essentialTime <= (totalAvailableTime - minimumBuffer)
    }
    
    var effectiveAvailableTime: TimeInterval {
        totalAvailableTime - effectiveBuffer
    }
}

