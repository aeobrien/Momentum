import ActivityKit
import Foundation

struct RoutineActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties
        var taskName: String
        var remainingTime: TimeInterval
        var isOverrun: Bool
        var taskEndTime: Date
        var scheduleOffsetString: String
    }
    
    // Fixed properties
    var routineName: String
}