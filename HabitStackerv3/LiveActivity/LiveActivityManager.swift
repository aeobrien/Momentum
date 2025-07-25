import Foundation
import ActivityKit

@available(iOS 16.1, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private init() {}
    
    func setupLiveActivities() {
        // This ensures the Live Activity system is initialized
        print("Live Activities enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled)")
        
        // Clean up any existing activities on setup
        endAllActivities()
        
        // Register for updates
        Task {
            for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                print("Activity enablement changed")
            }
        }
    }
    
    func endAllActivities() {
        let activities = Activity<RoutineActivityAttributes>.activities
        
        if !activities.isEmpty {
            print("🔵 LiveActivityManager: Ending \(activities.count) existing activities")
            
            Task {
                for activity in activities {
                    print("🔵 LiveActivityManager: Ending activity \(activity.id) with state \(activity.activityState)")
                    
                    // Try multiple approaches to ensure it's ended
                    do {
                        // First try normal end
                        await activity.end(nil, dismissalPolicy: .immediate)
                        
                        // If available in iOS 16.2+, also try ending with content state
                        if #available(iOS 16.2, *) {
                            let finalState = RoutineActivityAttributes.ContentState(
                                taskName: "App Closed",
                                remainingTime: 0,
                                isOverrun: false,
                                taskEndTime: Date(),
                                scheduleOffsetString: ""
                            )
                            await activity.end(using: finalState, dismissalPolicy: .immediate)
                        }
                    } catch {
                        print("🔴 LiveActivityManager: Error ending activity: \(error)")
                    }
                }
                print("🟢 LiveActivityManager: Finished ending all activities")
            }
        }
    }
}