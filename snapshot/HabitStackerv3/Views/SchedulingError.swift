//
//  SchedulingError.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 23/10/2024.
//

import Foundation

/// Errors related to scheduling routines
enum SchedulingError: Error, LocalizedError {
    case insufficientTime
    case invalidTimeRange
    case routineLoadError
    case schedulingFailure
    case optimizationError
    case invalidTaskReference(uuid: String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientTime:
            return "There is not enough time to schedule the selected routine."
        case .invalidTimeRange:
            return "The selected time range is invalid."
        case .routineLoadError:
            return "Failed to load the selected routine."
        case .schedulingFailure:
            return "Failed to generate the schedule."
        case .optimizationError:
            return "An error occurred during schedule optimization."
        case .invalidTaskReference(let uuid):
            return "Task with ID \(uuid) could not be found."
        }
    }
}

