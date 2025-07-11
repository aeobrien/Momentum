import CoreData

class CoreDataStack {
    
    private let containerName: String
    private let storeDescription: String?
    
    init(containerName: String, storeDescription: String? = nil) {
        self.containerName = containerName
        self.storeDescription = storeDescription
    }
    
    static let shared = CoreDataStack(containerName: "Momentum 3")
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: containerName)
        
        // Get the default store description
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description.")
        }
        
        // Set custom store location if provided
        if let storeName = storeDescription {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let storeURL = documentsDirectory.appendingPathComponent("\(storeName).sqlite")
            description.url = storeURL
        }
        
        // --- Enable Lightweight Migration --- 
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        // ----------------------------------
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                // Log detailed error information
                print("Unresolved error loading persistent store: \(error), \(error.userInfo)")
                // Non-CloudKit Core Data errors are critical
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
