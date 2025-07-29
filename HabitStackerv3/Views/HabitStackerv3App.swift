import SwiftUI
import WidgetKit
import ActivityKit
import UserNotifications

/// HabitStackerv3App is the main entry point for the Task Storage System application
@main
struct MomentumApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dataStoreManager = DataStoreManager.shared
    
    init() {
        UINavigationBar.appearance().prefersLargeTitles = false
        
        // Set portrait orientation lock
        AppDelegate.orientationLock = .portrait
        
        // Register custom value transformer for ChecklistItem
        ChecklistItemTransformer.register()
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environment(\.managedObjectContext, dataStoreManager.viewContext)
                .environmentObject(dataStoreManager)
                .id(dataStoreManager.storeChangeID)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    print("🔵 APP WILL TERMINATE: Notification received")
                    endAllLiveActivities()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { _ in
                    print("🔵 SCENE WILL DEACTIVATE: Notification received")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in
                    print("🔵 SCENE DID DISCONNECT: Notification received - ending all activities")
                    endAllLiveActivities()
                }
        }
    }
    
    private func endAllLiveActivities() {
        // Cancel all pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("🔵 END ALL ACTIVITIES: Cancelled all pending notifications")
        
        if #available(iOS 16.1, *) {
            let activities = Activity<RoutineActivityAttributes>.activities
            print("🔵 END ALL ACTIVITIES: Found \(activities.count) active activities")
            
            if !activities.isEmpty {
                // Create a dispatch group for synchronization
                let group = DispatchGroup()
                
                // End each activity synchronously on the main thread
                for activity in activities {
                    group.enter()
                    print("🔵 END ALL ACTIVITIES: Ending activity \(activity.id)")
                    
                    // Use async but wait on main thread
                    Task { @MainActor in
                        await activity.end(nil, dismissalPolicy: .immediate)
                        print("🟢 END ALL ACTIVITIES: Ended activity \(activity.id)")
                        group.leave()
                    }
                }
                
                // Block until all activities are ended (with timeout)
                let result = group.wait(timeout: .now() + 3.0)
                
                if result == .success {
                    print("🟢 END ALL ACTIVITIES: Successfully ended all activities")
                } else {
                    print("🔴 END ALL ACTIVITIES: Timeout while ending activities")
                }
                
                // Force a small delay to ensure the system processes the end requests
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    private func setupApp() async {
        let logger = AppLogger.create(subsystem: "com.app.Momentum", category: "AppLifecycle")
        
        logger.info("Application is starting up. Setting up Core Data.")

        // Initialize Core Data Stack
        let coreDataStack = CoreDataStack.shared
        logger.info("Core Data Stack initialized.")

        // --- Perform one-time task deduplication ---
        logger.info("Checking if task deduplication is needed...")
        // Ensure this runs *after* Core Data stack is ready
        // Using performAndWait to ensure it completes before app continues,
        // as it modifies data the UI might load immediately.
        // coreDataStack.viewContext.performAndWait {
        //      deduplicateTasksByName(context: coreDataStack.viewContext)
        // }
        logger.info("Task deduplication check completed. (Call commented out)")
        // --- End of Deduplication Code ---

        // Data Migration block already commented out here
        
        // Other setup tasks can go here
        logger.info("App setup completed.")
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all
    // Remove logger if it's only used for the deleted migration service
    // private let logger = AppLogger.create(subsystem: "com.app.AppDelegate", category: "Migration")
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Perform automatic migration if needed (before Core Data initialization)
        AutomaticMigration.shared.performMigrationIfNeeded()
        
        // Initialize iCloud backup manager and schedule automatic backups
        _ = iCloudBackupManager.shared
        iCloudBackupManager.shared.scheduleAutomaticBackup()
        
        // Setup Live Activities (this also cleans up stale ones)
        if #available(iOS 16.1, *) {
            LiveActivityManager.shared.setupLiveActivities()
        }
        
        return true
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("🔵 APP LIFECYCLE: applicationDidEnterBackground called")
        // Don't end activities here - let them continue in background
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        print("🔵 APP LIFECYCLE: applicationWillResignActive called")
        // This is called when app is about to move from active to inactive state
    }
    
    
    func applicationWillTerminate(_ application: UIApplication) {
        print("🔵 APP TERMINATE: applicationWillTerminate called")
        
        // Cancel all notifications immediately
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // End all Live Activities when app is terminated
        if #available(iOS 16.1, *) {
            let activities = Activity<RoutineActivityAttributes>.activities
            print("🔵 APP TERMINATE: Found \(activities.count) active activities")
            
            if !activities.isEmpty {
                // Try synchronous approach with RunLoop
                let runLoop = RunLoop.current
                var completed = false
                
                Task { @MainActor in
                    for activity in activities {
                        print("🔵 APP TERMINATE: Force ending activity \(activity.id)")
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                    completed = true
                }
                
                // Run the loop until completed or timeout
                let timeoutDate = Date(timeIntervalSinceNow: 2.0)
                while !completed && runLoop.run(mode: .default, before: timeoutDate) {
                    // Keep running until completed or timeout
                }
                
                print("🟢 APP TERMINATE: Activity cleanup completed")
            }
        }
    }
}

@available(iOS 13.0, *)
extension MomentumApp {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
