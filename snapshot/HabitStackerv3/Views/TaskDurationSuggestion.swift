import Foundation
import CoreData

struct TaskDurationSuggestion {
    let task: CDTask
    let currentDuration: Int // in minutes
    let suggestedDuration: Int // in minutes
    let averageCompletionTime: TimeInterval // in seconds
    let completionCount: Int
    
    var percentageDifference: Double {
        let current = Double(currentDuration)
        let suggested = Double(suggestedDuration)
        return abs(current - suggested) / current * 100
    }
    
    var changeDescription: String {
        if suggestedDuration < currentDuration {
            return "Task usually takes less time (\(suggestedDuration) min vs \(currentDuration) min)"
        } else {
            return "Task usually takes more time (\(suggestedDuration) min vs \(currentDuration) min)"
        }
    }
}