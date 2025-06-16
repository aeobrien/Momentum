import SwiftUI

/// HabitStackerv3App is the main entry point for the Task Storage System application
@main
struct MomentumApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    init() {
        UINavigationBar.appearance().prefersLargeTitles = false
        
        // Force portrait orientation
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        AppDelegate.orientationLock = .portrait
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
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
        // Remove Data Migration Call - No longer needed
        /*
        Task {
            let logger = AppLogger.create(subsystem: "com.app.AppDelegate", category: "Migration") // Define logger locally if needed for context
            do {
                // Calls to DataMigrationService removed as the service is deleted
                // let migrationService = DataMigrationService()
                // try await migrationService.migrateData()
                // let verificationResult = try await migrationService.verifyMigration()
                
                // ... migration verification logging removed ...

                logger.info("Old migration logic block skipped.")
            } catch {
                logger.error("Old migration logic block encountered error (should not happen)", error: error)
            }
        }
        */
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
