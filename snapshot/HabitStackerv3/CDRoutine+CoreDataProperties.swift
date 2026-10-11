//
//  CDRoutine+CoreDataProperties.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 06/11/2024.
//
//

import Foundation
import CoreData


extension CDRoutine {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDRoutine> {
        return NSFetchRequest<CDRoutine>(entityName: "CDRoutine")
    }

    @NSManaged public var uuid: UUID?
    @NSManaged public var name: String?
    @NSManaged public var createdOn: Date?
    @NSManaged public var lastUsed: Date?
    @NSManaged public var totalCompletions: Int32
    @NSManaged public var averageCompletionTime: Double
    @NSManaged public var taskRelations: NSSet?
    
    func update(from routine: Routine, context: NSManagedObjectContext) {
            self.uuid = UUID(uuidString: routine.id) ?? UUID()
            self.name = routine.name
            self.createdOn = routine.createdOn
            self.lastUsed = routine.metadata.lastUsed
            self.totalCompletions = Int32(routine.metadata.totalCompletions)
            self.averageCompletionTime = routine.metadata.averageCompletionTime
            
            // First, fetch all existing tasks that we'll need upfront with proper error handling
            let taskUUIDs = routine.taskUUIDs
            let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "uuid IN %@", taskUUIDs.map { UUID(uuidString: $0) ?? UUID() })
            
            do {
                let availableTasks = try context.fetch(fetchRequest)
                let taskDict = Dictionary(uniqueKeysWithValues: availableTasks.compactMap { task -> (String, CDTask)? in
                    guard let uuidString = task.uuid?.uuidString else { return nil }
                    return (uuidString, task)
                })
                
                // Remove existing relations first
                if let existingRelations = self.taskRelations as? Set<CDRoutineTask> {
                    existingRelations.forEach { context.delete($0) }
                }
                self.taskRelations = nil
                
                // Create new relations in order
                var newRelations = Set<CDRoutineTask>()
                
                for (index, taskUUID) in routine.taskUUIDs.enumerated() {
                    if let task = taskDict[taskUUID] {
                        let relation = CDRoutineTask(context: context)
                        relation.order = Int32(index)
                        relation.task = task
                        relation.routine = self
                        newRelations.insert(relation)
                        
                        AppLogger.create(subsystem: "com.app.CDRoutine", category: "Relationships")
                            .debug("Created relation for task: \(task.taskName ?? ""), order: \(index)")
                    } else {
                        AppLogger.create(subsystem: "com.app.CDRoutine", category: "Relationships")
                            .warning("Could not find task with UUID: \(taskUUID)")
                    }
                }
                
                // Set all relations at once
                self.taskRelations = newRelations as NSSet
                
                AppLogger.create(subsystem: "com.app.CDRoutine", category: "Relationships")
                    .info("Successfully updated routine with \(newRelations.count) task relations")
                
            } catch {
                AppLogger.create(subsystem: "com.app.CDRoutine", category: "Relationships")
                    .error("Failed to fetch tasks for routine relationships", error: error)
            }
        }

}

// MARK: Generated accessors for taskRelations
extension CDRoutine {

    @objc(addTaskRelationsObject:)
    @NSManaged public func addToTaskRelations(_ value: CDRoutineTask)

    @objc(removeTaskRelationsObject:)
    @NSManaged public func removeFromTaskRelations(_ value: CDRoutineTask)

    @objc(addTaskRelations:)
    @NSManaged public func addToTaskRelations(_ values: NSSet)

    @objc(removeTaskRelations:)
    @NSManaged public func removeFromTaskRelations(_ values: NSSet)

}

extension CDRoutine : Identifiable {

}
