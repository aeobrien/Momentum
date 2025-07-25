import Foundation
import ActivityKit

@available(iOS 16.1, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private init() {}
    
    func setupLiveActivities() {
        // This ensures the Live Activity system is initialized
        print("Live Activities enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled)")
        
        // Register for updates
        Task {
            for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                print("Activity enablement changed")
            }
        }
    }
}