//
//  CDTask+CoreDataProperties.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 06/11/2024.
//
//

import Foundation
import CoreData


extension CDTask {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTask> {
        return NSFetchRequest<CDTask>(entityName: "CDTask")
    }

    // MARK: - Core Properties
    @NSManaged public var uuid: UUID?
    @NSManaged public var taskName: String?
    @NSManaged public var essentiality: Int16
    @NSManaged public var minDuration: Int32 // Duration in minutes
    @NSManaged public var maxDuration: Int32 // Duration in minutes
    @NSManaged public var lastCompleted: Date?
    
    /// Repetition interval in seconds.
    /// 0 means repeat daily at midnight.
    /// > 0 means repeat after that many seconds pass since last completion.
    /// nil or < 0 means does not repeat automatically.
    @NSManaged public var repetitionInterval: Int32
    
    /// Flag indicating if this task is specific to a routine session and should not appear in the general to-do list.
    /// Defaults to false when creating new tasks.
    @NSManaged public var isSessionTask: Bool
    
    // MARK: - Relationships
    @NSManaged public var routineRelations: NSSet?

    // MARK: - Dependency Properties (Added manually)
    @NSManaged public var dependsOn: Set<CDTask>?
    @NSManaged public var dependedOnBy: Set<CDTask>?
}

// MARK: Generated accessors for routineRelations
extension CDTask {

    @objc(addRoutineRelationsObject:)
    @NSManaged public func addToRoutineRelations(_ value: CDRoutineTask)

    @objc(removeRoutineRelationsObject:)
    @NSManaged public func removeFromRoutineRelations(_ value: CDRoutineTask)

    @objc(addRoutineRelations:)
    @NSManaged public func addToRoutineRelations(_ values: NSSet)

    @objc(removeRoutineRelations:)
    @NSManaged public func removeFromRoutineRelations(_ values: NSSet)

}

// MARK: - Identifiable Conformance
extension CDTask : Identifiable {
    // ID is implicitly handled by CoreData's objectID, but uuid is used for custom identification
}

// MARK: - Computed Properties (Added manually)
extension CDTask {
    var allPrerequisiteTasks: Set<CDTask> {
        guard let dependencies = dependsOn else { return [] }
        return dependencies.union(dependencies.flatMap { $0.allPrerequisiteTasks })
    }
    
    var isEligibleToSchedule: Bool {
        guard let dependencies = dependsOn else { return true }
        return dependencies.allSatisfy { $0.lastCompleted != nil }
    }
}

