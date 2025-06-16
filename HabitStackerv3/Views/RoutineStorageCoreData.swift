import CoreData
import Foundation
import OSLog

final class RoutineStorageCoreData: RoutineStorageInterface {
    private let context: NSManagedObjectContext
    private let logger: Logger
    private let activeRoutineKey = "activeRoutineID"
    
    static let shared = RoutineStorageCoreData()
    
    private init() {
        self.context = CoreDataStack.shared.viewContext
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineStorageCoreData")
    }
    
    // MARK: - RoutineStorageInterface Methods
    
    func createRoutine(_ routine: Routine) -> Result<Routine, Error> {
        logger.debug("Creating routine: \(routine.name, privacy: .public)")
        
        let cdRoutine = CDRoutine(context: context)
        cdRoutine.updateCDRoutine(from: routine, context: context)
        
        do {
            try context.save()
            logger.info("Successfully created routine: \(routine.name, privacy: .public)")
            return .success(cdRoutine.toDomainModel())
        } catch {
            logger.error("Failed to create routine: \(error.localizedDescription)")
            return .failure(RoutineStorageError.storageFailure)
        }
    }
    
    func fetchRoutines() -> Result<[Routine], Error> {
        logger.debug("Fetching all routines")
        
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        
        do {
            let cdRoutines = try context.fetch(fetchRequest)
            let routines = cdRoutines.map { $0.toDomainModel() }
            logger.info("Successfully fetched \(routines.count) routines")
            return .success(routines)
        } catch {
            logger.error("Failed to fetch routines: \(error.localizedDescription)")
            return .failure(RoutineStorageError.storageFailure)
        }
    }
    
    func updateRoutine(_ routine: Routine) -> Result<Routine, Error> {
        logger.debug("Updating routine: \(routine.name, privacy: .public)")
        
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        guard let routineUUID = UUID(uuidString: routine.id) else {
            logger.error("Invalid UUID string for routine update: \(routine.id, privacy: .public)")
            return .failure(RoutineStorageError.invalidUUID)
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", routineUUID as CVarArg)
        
        do {
            guard let cdRoutine = try context.fetch(fetchRequest).first else {
                logger.error("Routine not found for update: \(routine.id, privacy: .public)")
                return .failure(RoutineStorageError.routineNotFound)
            }
            
            cdRoutine.updateCDRoutine(from: routine, context: context)
            try context.save()
            
            logger.info("Successfully updated routine: \(routine.name, privacy: .public)")
            return .success(cdRoutine.toDomainModel())
        } catch {
            logger.error("Failed to update routine: \(error.localizedDescription)")
            return .failure(RoutineStorageError.storageFailure)
        }
    }
    
    func deleteRoutine(id: String) -> Result<Void, Error> {
        logger.debug("Deleting routine: \(id, privacy: .public)")
        
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        guard let routineUUID = UUID(uuidString: id) else {
            logger.error("Invalid UUID string for routine delete: \(id, privacy: .public)")
            return .failure(RoutineStorageError.invalidUUID)
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", routineUUID as CVarArg)
        
        do {
            guard let cdRoutine = try context.fetch(fetchRequest).first else {
                logger.error("Routine not found for deletion: \(id, privacy: .public)")
                return .failure(RoutineStorageError.routineNotFound)
            }
            
            // Delete all task relations first
            if let relations = cdRoutine.taskRelations as? Set<CDRoutineTask> {
                for relation in relations {
                    context.delete(relation)
                }
            }
            
            context.delete(cdRoutine)
            try context.save()
            
            logger.info("Successfully deleted routine: \(id, privacy: .public)")
            return .success(())
        } catch {
            logger.error("Failed to delete routine: \(error.localizedDescription)")
            return .failure(RoutineStorageError.storageFailure)
        }
    }
    
    func reorderTask(inRoutine routineID: String, from: Int, to: Int) -> Result<Void, Error> {
        logger.debug("Reordering task in routine \(routineID, privacy: .public) from \(from) to \(to)")
        
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        guard let routineUUID = UUID(uuidString: routineID) else {
             logger.error("Invalid UUID string for routine reorder: \(routineID, privacy: .public)")
             return .failure(RoutineStorageError.invalidUUID)
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", routineUUID as CVarArg)
        
        do {
            guard let cdRoutine = try context.fetch(fetchRequest).first else {
                logger.error("Routine not found for reordering: \(routineID, privacy: .public)")
                return .failure(RoutineStorageError.routineNotFound)
            }
            
            guard let relations = cdRoutine.taskRelations?.allObjects as? [CDRoutineTask] else {
                logger.error("No task relations found for routine: \(routineID, privacy: .public)")
                return .failure(RoutineStorageError.invalidIndices)
            }
            
            let sortedRelations = relations.sorted { $0.order < $1.order }
            guard from >= 0, from < sortedRelations.count,
                  to >= 0, to < sortedRelations.count else {
                logger.error("Invalid indices for reordering: from \(from) to \(to)")
                return .failure(RoutineStorageError.invalidIndices)
            }
            
            // Update orders
            let movedRelation = sortedRelations[from]
            if from < to {
                for i in (from + 1)...to {
                    sortedRelations[i].order -= 1
                }
            } else {
                for i in to..<from {
                    sortedRelations[i].order += 1
                }
            }
            movedRelation.order = Int32(to)
            
            try context.save()
            
            logger.info("Successfully reordered tasks in routine: \(routineID, privacy: .public)")
            return .success(())
        } catch {
            logger.error("Failed to reorder tasks: \(error.localizedDescription)")
            return .failure(RoutineStorageError.storageFailure)
        }
    }
    
    // MARK: - Active Routine Management
    
    func setActiveRoutine(id: String) {
        UserDefaults.standard.set(id, forKey: activeRoutineKey)
        logger.info("Set active routine: \(id, privacy: .public)")
    }
    
    func fetchActiveRoutine() -> Routine? {
        guard let activeID = UserDefaults.standard.string(forKey: activeRoutineKey) else {
            return nil
        }
        
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        guard let routineUUID = UUID(uuidString: activeID) else {
             logger.error("Invalid active routine UUID string stored: \(activeID, privacy: .public)")
             clearActiveRoutine()
             return nil
        }
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", routineUUID as CVarArg)
        
        do {
            guard let cdRoutine = try context.fetch(fetchRequest).first else {
                logger.debug("No active routine found for ID: \(activeID, privacy: .public)")
                return nil
            }
            
            let routine = cdRoutine.toDomainModel()
            logger.debug("Successfully fetched active routine: \(routine.name, privacy: .public)")
            return routine
        } catch {
            logger.error("Failed to fetch active routine: \(error.localizedDescription)")
            return nil
        }
    }
    
    func clearActiveRoutine() {
        UserDefaults.standard.removeObject(forKey: activeRoutineKey)
        logger.info("Cleared active routine")
    }
    
    // MARK: - Testing Support
    
    #if DEBUG
    func resetStorage() throws {
        logger.debug("Resetting routine storage")
        
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CDRoutine.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
            logger.info("Successfully reset routine storage")
        } catch {
            logger.error("Failed to reset storage: \(error.localizedDescription)")
            throw RoutineStorageError.storageFailure
        }
    }
    #endif
}

