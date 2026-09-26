import CoreData
import Foundation
import OSLog

extension CDRoutine {
    // Convert Core Data object to domain model
    func toDomainModel() -> Routine {
        // Safely get all relations and convert to array first
        let relations = taskRelations?.allObjects as? [CDRoutineTask] ?? []
        
        // Filter out any invalid relations and sort
        let sortedRelations = relations
            .filter { $0.isDeleted == false && $0.task != nil } // Ensure relation and task exist
            .sorted { $0.order < $1.order }
        
        // Safely extract UUIDs, filtering out any nil values
        let taskUUIDs = sortedRelations.compactMap { relation -> String? in
            guard let task = relation.task,
                  task.isDeleted == false,
                  let uuid = task.uuid?.uuidString else {
                return nil
            }
            return uuid
        }
        
        // Create metadata with safe defaults
        let metadata = RoutineMetadata(
            // creationDate: self.createdOn ?? Date(), // Use actual property if different
            lastUsed: self.lastUsed ?? Date(), // Provide default Date() if nil
            totalCompletions: Int(self.totalCompletions), // Cast if needed
            averageCompletionTime: self.averageCompletionTime // Assuming this property exists
        )
        
        // Create and return Routine domain model with safe values
        return Routine(
            id: self.uuid?.uuidString ?? UUID().uuidString,
            name: self.name ?? "",
            createdOn: self.createdOn ?? Date(), // Uncommented and assuming self.createdOn exists
            taskUUIDs: taskUUIDs,
            metadata: metadata
        )
    }

    // Update Core Data object from Routine domain model
    func updateCDRoutine(from routine: Routine, context: NSManagedObjectContext) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CDRoutineUpdate")
        
        if self.uuid?.uuidString != routine.id {
             if let newUUID = UUID(uuidString: routine.id) {
                 self.uuid = newUUID
                 logger.debug("Updating routine UUID to: \(newUUID.uuidString, privacy: .public)")
             } else {
                 logger.error("Invalid UUID string provided for routine update: \(routine.id, privacy: .public)")
                 // Don't change UUID if the new one is invalid
             }
         }
        
        self.name = routine.name
        // Update metadata properties
        self.lastUsed = routine.metadata.lastUsed
        self.totalCompletions = Int32(routine.metadata.totalCompletions) // Corrected cast to Int32
        self.averageCompletionTime = routine.metadata.averageCompletionTime // Assuming Double/TimeInterval
        self.createdOn = routine.createdOn // Assuming Date

        // --- Handle Task Relationships ---
        // 1. Get current relations
        let currentRelations = self.taskRelations as? Set<CDRoutineTask> ?? Set()
        let currentTaskUUIDs = Set(currentRelations.compactMap { $0.task?.uuid?.uuidString })
        
        // 2. Get desired task UUIDs from domain model
        let desiredTaskUUIDs = Set(routine.taskUUIDs)
        
        // 3. Find Tasks to Add
        let tasksToAdd = desiredTaskUUIDs.subtracting(currentTaskUUIDs)
        for (index, taskUUIDString) in routine.taskUUIDs.enumerated() {
            if tasksToAdd.contains(taskUUIDString) {
                // Fetch the CDTask corresponding to taskUUIDString
                let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
                 guard let taskUUID = UUID(uuidString: taskUUIDString) else {
                     logger.error("Invalid UUID string \(taskUUIDString, privacy: .public) in routine task list, cannot link task.")
                     continue // Skip this task
                 }
                fetchRequest.predicate = NSPredicate(format: "uuid == %@", taskUUID as CVarArg)
                fetchRequest.fetchLimit = 1
                
                do {
                    if let taskToAdd = try context.fetch(fetchRequest).first {
                        let newRelation = CDRoutineTask(context: context)
                        newRelation.routine = self
                        newRelation.task = taskToAdd
                        newRelation.order = Int32(index)
                        logger.debug("Adding task '\(taskToAdd.taskName ?? "", privacy: .public)' to routine '\(self.name ?? "", privacy: .public)' at order \(index)")
                    } else {
                         logger.warning("Could not find CDTask with UUID \(taskUUIDString, privacy: .public) to add to routine.")
                    }
                } catch {
                     logger.error("Error fetching CDTask with UUID \(taskUUIDString, privacy: .public) for adding: \(error.localizedDescription)")
                }
            }
        }

        // 4. Find Relations to Remove
        let tasksToRemove = currentTaskUUIDs.subtracting(desiredTaskUUIDs)
        let relationsToRemove = currentRelations.filter { tasksToRemove.contains($0.task?.uuid?.uuidString ?? "") }
        for relationToRemove in relationsToRemove {
            logger.debug("Removing task '\(relationToRemove.task?.taskName ?? "", privacy: .public)' from routine '\(self.name ?? "", privacy: .public)'")
            context.delete(relationToRemove)
        }

        // 5. Update Order for Existing Tasks
        let remainingRelations = currentRelations.filter { desiredTaskUUIDs.contains($0.task?.uuid?.uuidString ?? "") }
        for relation in remainingRelations {
            if let desiredIndex = routine.taskUUIDs.firstIndex(of: relation.task?.uuid?.uuidString ?? "") {
                let desiredOrder = Int32(desiredIndex)
                if relation.order != desiredOrder {
                    logger.debug("Updating order for task '\(relation.task?.taskName ?? "", privacy: .public)' from \(relation.order) to \(desiredOrder)")
                    relation.order = desiredOrder
                }
            }
        }
        
        logger.info("Finished updating task relations for routine '\(self.name ?? "", privacy: .public)'")
    }
}

// Note: Ensure Routine and RoutineMetadata struct definitions match the properties used here.

