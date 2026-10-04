import CoreData
import Foundation
import OSLog

final class TaskStorageCoreData: TaskStorageInterface {
    private var context: NSManagedObjectContext {
        DataStoreManager.shared.viewContext
    }
    private let logger: Logger
    
    static let shared = TaskStorageCoreData()
    
    private init() {
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TaskStorageCoreData")
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDataStoreChange),
            name: .dataStoreDidChange,
            object: nil
        )
    }
    
    @objc private func handleDataStoreChange() {
        logger.info("Data store changed, context updated")
    }
    
    // MARK: - TaskStorageInterface Methods
    
    func createTask(_ task: CustomTask) -> Result<CustomTask, Error> {
        logger.debug("Creating task: \(task.taskName, privacy: .public)")
        
        let cdTask = CDTask(context: context)
        cdTask.updateCDTask(from: task)
        
        do {
            try context.save()
            logger.info("Successfully created task: \(task.taskName, privacy: .public)")
            return .success(cdTask.toDomainModel())
        } catch {
            logger.error("Failed to create task: \(error.localizedDescription)")
            return .failure(TaskStorageError.storageFailure)
        }
    }
    
    func fetchTasks() -> Result<[CustomTask], Error> {
        logger.debug("Fetching all tasks")
        
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        
        do {
            let cdTasks = try context.fetch(fetchRequest)
            let tasks = cdTasks.map { $0.toDomainModel() }
            logger.info("Successfully fetched \(tasks.count) tasks")
            return .success(tasks)
        } catch {
            logger.error("Failed to fetch tasks: \(error.localizedDescription)")
            return .failure(TaskStorageError.storageFailure)
        }
    }
    
    func updateTask(_ task: CustomTask) -> Result<CustomTask, Error> {
        logger.debug("Updating task: \(task.taskName, privacy: .public)")
        
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        guard let taskUUID = UUID(uuidString: task.uuid) else {
            logger.error("Invalid UUID string provided for update: \(task.uuid, privacy: .public)")
            return .failure(TaskStorageError.invalidUUID)
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", taskUUID as CVarArg)
        
        do {
            guard let cdTask = try context.fetch(fetchRequest).first else {
                logger.error("Task not found for update: \(task.uuid, privacy: .public)")
                return .failure(TaskStorageError.taskNotFound)
            }
            
            cdTask.updateCDTask(from: task)
            try context.save()
            
            logger.info("Successfully updated task: \(task.taskName, privacy: .public)")
            return .success(cdTask.toDomainModel())
        } catch {
            logger.error("Failed to update task: \(error.localizedDescription)")
            return .failure(TaskStorageError.storageFailure)
        }
    }
    
    func deleteTask(uuid: String) -> Result<Void, Error> {
        logger.debug("Deleting task: \(uuid, privacy: .public)")
        
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        guard let taskUUID = UUID(uuidString: uuid) else {
            logger.error("Invalid UUID string provided for delete: \(uuid, privacy: .public)")
            return .failure(TaskStorageError.invalidUUID)
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", taskUUID as CVarArg)
        
        do {
            guard let cdTask = try context.fetch(fetchRequest).first else {
                logger.error("Task not found for deletion: \(uuid, privacy: .public)")
                return .failure(TaskStorageError.taskNotFound)
            }
            
            // Remove all routine relations first
            if let relations = cdTask.routineRelations as? Set<CDRoutineTask> {
                for relation in relations {
                    context.delete(relation)
                }
            }
            
            context.delete(cdTask)
            try context.save()
            
            logger.info("Successfully deleted task: \(uuid, privacy: .public)")
            return .success(())
        } catch {
            logger.error("Failed to delete task: \(error.localizedDescription)")
            return .failure(TaskStorageError.storageFailure)
        }
    }
    
    func fetchTask(by uuid: String) -> CustomTask? {
        logger.debug("Fetching task by UUID: \(uuid, privacy: .public)")
        
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        guard let taskUUID = UUID(uuidString: uuid) else {
            logger.error("Invalid UUID string provided for fetch: \(uuid, privacy: .public)")
            return nil
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", taskUUID as CVarArg)
        
        do {
            guard let cdTask = try context.fetch(fetchRequest).first else {
                logger.debug("No task found for UUID: \(uuid, privacy: .public)")
                return nil
            }
            
            let task = cdTask.toDomainModel()
            logger.debug("Successfully fetched task: \(task.taskName, privacy: .public)")
            return task
        } catch {
            logger.error("Failed to fetch task by UUID: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Testing Support
    
    #if DEBUG
    func resetStorage() throws {
        logger.debug("Resetting task storage")
        
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CDTask.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
            logger.info("Successfully reset task storage")
        } catch {
            logger.error("Failed to reset storage: \(error.localizedDescription)")
            throw TaskStorageError.storageFailure
        }
    }
    #endif
}
