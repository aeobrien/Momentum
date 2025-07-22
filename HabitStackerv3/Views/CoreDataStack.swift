import CoreData

class CoreDataStack {
    
    private let containerName: String
    private let storeDescription: String?
    private static var isInitialized = false
    
    init(containerName: String, storeDescription: String? = nil) {
        self.containerName = containerName
        self.storeDescription = storeDescription
        
        // Log initialization to track any duplicate attempts
        print("[CoreDataStack] Initializing with container: \(containerName), store: \(storeDescription ?? "default")")
    }
    
    static let shared = CoreDataStack(containerName: "Momentum 3")
    
    lazy var persistentContainer: NSPersistentContainer = {
        // Check if already initialized to prevent duplicate loading
        if CoreDataStack.isInitialized {
            print("[CoreDataStack] WARNING: Attempting to initialize persistent container multiple times!")
        }
        
        print("[CoreDataStack] Loading persistent container: \(containerName)")
        let container = NSPersistentContainer(name: containerName)
        
        // Get the default store description
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description.")
        }
        
        // Set store location based on testing mode
        let isTestingMode = UserDefaults.standard.bool(forKey: "isTestingModeEnabled")
        let storeName = isTestingMode ? "Momentum 3 Testing" : "Momentum 3"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let storeURL = documentsDirectory.appendingPathComponent("\(storeName).sqlite")
        description.url = storeURL
        print("[CoreDataStack] Using store: \(storeName) at: \(storeURL.path)")
        
        // --- Enable Lightweight Migration --- 
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        // ----------------------------------
        
        // Enable persistent history tracking to match previous store configuration
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                // Log detailed error information
                print("[CoreDataStack] ERROR loading persistent store: \(error), \(error.userInfo)")
                // Non-CloudKit Core Data errors are critical
                fatalError("Failed to load Core Data stack: \(error)")
            } else {
                print("[CoreDataStack] Successfully loaded store at: \(storeDescription.url?.path ?? "unknown")")
                CoreDataStack.isInitialized = true
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
    
}
