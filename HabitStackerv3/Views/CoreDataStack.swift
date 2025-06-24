import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()
    
    private init() {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Momentum 3")
        
        // Get the default store description
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description.")
        }
        
        // --- Enable Lightweight Migration --- 
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        // ----------------------------------
        
        // Enable persistent history tracking for multi-device sync if needed later
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        container.loadPersistentStores { (storeDescription, error) in // Variable name is fine here
            if let error = error as NSError? { // Cast to NSError for more details
                // Log detailed error information
                print("Unresolved error loading persistent store: \(error), \(error.userInfo)")
                // Consider more robust error handling than fatalError in production
                fatalError("Failed to load Core Data stack: \(error)")
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
