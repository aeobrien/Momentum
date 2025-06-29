import CoreData
import CloudKit

class CoreDataStack {
    static let shared = CoreDataStack()
    
    private init() {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentCloudKitContainer(name: "Momentum 3")
        
        // Get the default store description
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description.")
        }
        
        // --- Enable Lightweight Migration --- 
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        // ----------------------------------
        
        // Enable persistent history tracking for CloudKit sync
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        // Configure for CloudKit - this enables remote change notifications
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Set CloudKit container options
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.AOTondra.Momentum"
        )
        
        container.loadPersistentStores { (storeDescription, error) in // Variable name is fine here
            if let error = error as NSError? { // Cast to NSError for more details
                // Log detailed error information
                print("Unresolved error loading persistent store: \(error), \(error.userInfo)")
                
                // Update sync manager with error
                CloudKitSyncManager.shared.handleError(error)
                
                // Check if this is a CloudKit-specific error
                if let ckError = error as? CKError {
                    // Handle CloudKit errors gracefully
                    print("CloudKit error during store load: \(ckError)")
                    // The app should continue to work with local storage
                } else {
                    // Non-CloudKit Core Data errors are critical
                    fatalError("Failed to load Core Data stack: \(error)")
                }
            } else {
                // Store loaded successfully
                CloudKitSyncManager.shared.checkCloudKitStatus()
            }
        }
        
        // Merge changes from parent contexts automatically
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Configure view context to prevent conflicts
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.shouldDeleteInaccessibleFaults = true
        
        return container
    }()
    
    // Main context for UI operations
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    // Background context for operations that shouldn't block the UI
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // Save the main context
    func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                // Replace this with your logger later
                print("Error saving context: \(error)")
            }
        }
    }
    
    // Save a specific context
    func save(_ context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this with your logger later
                print("Error saving context: \(error)")
            }
        }
    }
    
    // Perform work on a background context
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let context = newBackgroundContext()
        context.perform {
            block(context)
            self.save(context)
        }
    }
    
    // Check if iCloud is available
    var isCloudKitAvailable: Bool {
        if let token = FileManager.default.ubiquityIdentityToken {
            print("iCloud is available with token: \(token)")
            return true
        } else {
            print("iCloud is not available - user not signed in")
            return false
        }
    }
    
    // Handle CloudKit sync errors
    func handleCloudKitError(_ error: Error) {
        // Delegate error handling to the sync manager
        CloudKitSyncManager.shared.handleError(error)
        
        guard let ckError = error as? CKError else {
            print("Non-CloudKit error: \(error)")
            return
        }
        
        switch ckError.code {
        case .networkUnavailable:
            print("Network unavailable - data will sync when connection restored")
        case .networkFailure:
            print("Network failure - data will sync when connection restored")
        case .quotaExceeded:
            print("iCloud storage quota exceeded")
        case .notAuthenticated:
            print("User not signed into iCloud")
        case .permissionFailure:
            print("iCloud permission denied")
        case .accountTemporarilyUnavailable:
            print("iCloud account temporarily unavailable")
        default:
            print("CloudKit error: \(ckError)")
        }
    }
    
    // Setup notification observer for remote changes
    func setupRemoteChangeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator
        )
    }
    
    @objc private func handleRemoteChange(_ notification: Notification) {
        print("Remote CloudKit changes detected")
        // The viewContext will automatically merge these changes due to
        // automaticallyMergesChangesFromParent = true
        
        // Update sync manager
        CloudKitSyncManager.shared.updateLastSyncDate()
    }
}
