import SwiftUI
import WidgetKit
import ActivityKit

/// HabitStackerv3App is the main entry point for the Task Storage System application
@main
struct MomentumApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dataStoreManager = DataStoreManager.shared
    
    init() {
        UINavigationBar.appearance().prefersLargeTitles = false
        
        // Set portrait orientation lock
        AppDelegate.orientationLock = .portrait
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
        if #available(iOS 16.1, *) {
            let activities = Activity<RoutineActivityAttributes>.activities
            print("🔵 END ALL ACTIVITIES: Found \(activities.count) active activities")
            
            // Use a semaphore to make this synchronous
            let semaphore = DispatchSemaphore(value: 0)
            
            Task {
                for activity in activities {
                    print("🔵 END ALL ACTIVITIES: Ending activity \(activity.id)")
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                print("🟢 END ALL ACTIVITIES: Finished ending all activities")
                semaphore.signal()
            }
            
            // Wait for completion (with timeout)
            _ = semaphore.wait(timeout: .now() + 2.0)
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
        
        // Setup Live Activities
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
        // End all Live Activities when app is terminated
        if #available(iOS 16.1, *) {
            print("🔵 APP TERMINATE: Found \(Activity<RoutineActivityAttributes>.activities.count) active activities")
            Task {
                for activity in Activity<RoutineActivityAttributes>.activities {
                    print("🔵 APP TERMINATE: Ending activity \(activity.id)")
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                print("🟢 APP TERMINATE: Finished ending all activities")
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
