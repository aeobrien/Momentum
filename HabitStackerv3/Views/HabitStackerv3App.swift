import SwiftUI

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
        
        return true
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@available(iOS 13.0, *)
extension MomentumApp {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
