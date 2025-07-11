import CoreData
import Foundation

class CoreDataMigration {
    static let shared = CoreDataMigration()
    private init() {}
    
    func migrateFromOldStore() {
        // Debug: List all SQLite files in the documents directory
        debugPrintAllStores()
        
        // Check if migration has already been performed
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "HasMigratedFromMomentumToMomentum3") {
            print("Migration already performed")
            // Uncomment to force re-migration during testing:
            // defaults.set(false, forKey: "HasMigratedFromMomentumToMomentum3")
            return
        }
        
        // Try multiple possible store names
        let possibleStoreNames = ["Momentum.sqlite", "HabitStacker.sqlite", "HabitStackerv3.sqlite"]
        var oldStoreURL: URL?
        
        for storeName in possibleStoreNames {
            let url = getStoreURL(named: storeName)
            if FileManager.default.fileExists(atPath: url.path) {
                oldStoreURL = url
                print("Found old store: \(storeName) at: \(url.path)")
                break
            }
        }
        
        guard let oldStoreURL = oldStoreURL else {
            print("No old store found. Tried: \(possibleStoreNames)")
            return
        }
        
        // Create old container using the same model as the new container
        let oldContainer = NSPersistentContainer(name: "Momentum 3")
        
        // Configure old container to use the old store URL
        let oldStoreDescription = NSPersistentStoreDescription(url: oldStoreURL)
        // Disable automatic migration completely
        oldStoreDescription.shouldInferMappingModelAutomatically = false
        oldStoreDescription.shouldMigrateStoreAutomatically = false
        oldStoreDescription.type = NSSQLiteStoreType
        // Enable persistent history tracking to match the original store
        oldStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        // Set to read-only to avoid any write attempts
        oldStoreDescription.isReadOnly = true
        oldContainer.persistentStoreDescriptions = [oldStoreDescription]
        
        // Load old store
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        oldContainer.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("Failed to load old store: \(error)")
                loadError = error
            } else {
                print("Successfully loaded old store from: \(storeDescription.url?.path ?? "unknown")")
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        if loadError != nil {
            print("Aborting migration due to load error")
            return
        }
        
        // Get contexts
        let oldContext = oldContainer.viewContext
        let newContext = DataStoreManager.shared.viewContext
        
        do {
            // Migrate Tasks
            let taskFetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "CDTask")
            let oldTasks = try oldContext.fetch(taskFetchRequest)
            
            print("Found \(oldTasks.count) tasks to migrate")
            
            for oldTask in oldTasks {
                // Create new task
                let newTask = CDTask(context: newContext)
                
                // Copy basic attributes
                newTask.taskName = oldTask.value(forKey: "taskName") as? String ?? ""
                newTask.uuid = oldTask.value(forKey: "uuid") as? UUID ?? UUID()
                newTask.minDuration = oldTask.value(forKey: "minDuration") as? Int32 ?? 0
                newTask.maxDuration = oldTask.value(forKey: "maxDuration") as? Int32 ?? 0
                newTask.essentiality = oldTask.value(forKey: "essentiality") as? Int16 ?? 0
                newTask.repetitionInterval = oldTask.value(forKey: "repetitionInterval") as? Int32 ?? 0
                newTask.isSessionTask = oldTask.value(forKey: "isSessionTask") as? Bool ?? false
                newTask.lastCompleted = oldTask.value(forKey: "lastCompleted") as? Date
                
                // Set default values for new attributes
                newTask.shouldTrackAverageTime = false
                
                // Handle nextDueDate if it exists in old model
                if let nextDueDate = oldTask.value(forKey: "nextDueDate") as? Date {
                    newTask.nextDueDate = nextDueDate
                }
            }
            
            // Migrate Routines
            let routineFetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "CDRoutine")
            let oldRoutines = try oldContext.fetch(routineFetchRequest)
            
            print("Found \(oldRoutines.count) routines to migrate")
            
            // Create a mapping of old task UUIDs to new tasks
            let newTaskFetchRequest = NSFetchRequest<CDTask>(entityName: "CDTask")
            let newTasks = try newContext.fetch(newTaskFetchRequest)
            var newTasksByUUID: [UUID: CDTask] = [:]
            for task in newTasks {
                if let uuid = task.uuid {
                    newTasksByUUID[uuid] = task
                }
            }
            
            for oldRoutine in oldRoutines {
                let newRoutine = CDRoutine(context: newContext)
                
                // Copy routine attributes
                newRoutine.name = oldRoutine.value(forKey: "name") as? String ?? ""
                newRoutine.uuid = oldRoutine.value(forKey: "uuid") as? UUID ?? UUID()
                newRoutine.createdOn = oldRoutine.value(forKey: "createdOn") as? Date ?? Date()
                newRoutine.lastUsed = oldRoutine.value(forKey: "lastUsed") as? Date ?? Date()
                newRoutine.totalCompletions = oldRoutine.value(forKey: "totalCompletions") as? Int32 ?? 0
                newRoutine.averageCompletionTime = oldRoutine.value(forKey: "averageCompletionTime") as? Double ?? 0
                
                // Migrate routine-task relationships
                if let oldTaskRelations = oldRoutine.value(forKey: "taskRelations") as? Set<NSManagedObject> {
                    for oldRelation in oldTaskRelations {
                        if let oldTaskInRelation = oldRelation.value(forKey: "task") as? NSManagedObject,
                           let taskUUID = oldTaskInRelation.value(forKey: "uuid") as? UUID,
                           let newTask = newTasksByUUID[taskUUID] {
                            
                            let newRelation = CDRoutineTask(context: newContext)
                            newRelation.order = oldRelation.value(forKey: "order") as? Int32 ?? 0
                            newRelation.routine = newRoutine
                            newRelation.task = newTask
                        }
                    }
                }
            }
            
            // Save the new context
            try newContext.save()
            
            // Mark migration as complete
            defaults.set(true, forKey: "HasMigratedFromMomentumToMomentum3")
            
            print("Migration completed successfully!")
            print("Migrated \(oldTasks.count) tasks and \(oldRoutines.count) routines")
            
        } catch {
            print("Migration failed: \(error)")
        }
    }
    
    private func getStoreURL(named storeName: String) -> URL {
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        return storeDirectory.appendingPathComponent(storeName)
    }
    
    private func debugPrintAllStores() {
        print("\n=== Core Data Store Debug Info ===")
        
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        print("Store directory: \(storeDirectory.path)")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
            let sqliteFiles = files.filter { $0.pathExtension == "sqlite" || $0.pathExtension == "sqlite-shm" || $0.pathExtension == "sqlite-wal" }
            
            print("Found \(sqliteFiles.count) SQLite-related files:")
            for file in sqliteFiles {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                let size = attributes[.size] as? Int ?? 0
                print("  - \(file.lastPathComponent) (size: \(size) bytes)")
            }
        } catch {
            print("Error listing store directory: \(error)")
        }
        
        print("=================================\n")
    }
    
    func importSQLiteFile(from sourceURL: URL) {
        print("\n=== Importing SQLite File ===")
        
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        let destinationURL = storeDirectory.appendingPathComponent("Momentum.sqlite")
        
        do {
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the SQLite file
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // Also copy -shm and -wal files if they exist
            let shmSource = sourceURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let walSource = sourceURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            let shmDest = destinationURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let walDest = destinationURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            
            if FileManager.default.fileExists(atPath: shmSource.path) {
                try FileManager.default.copyItem(at: shmSource, to: shmDest)
            }
            
            if FileManager.default.fileExists(atPath: walSource.path) {
                try FileManager.default.copyItem(at: walSource, to: walDest)
            }
            
            print("Successfully imported SQLite file to: \(destinationURL.path)")
            
            // Reset migration flag to allow re-migration
            UserDefaults.standard.set(false, forKey: "HasMigratedFromMomentumToMomentum3")
            
        } catch {
            print("Error importing SQLite file: \(error)")
        }
    }
}