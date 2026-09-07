//
//  CDTask+CoreDataProperties.swift
//  Momentum
//
//  Created by Aidan O'Brien on 24/06/2025.
//
//

import Foundation
import CoreData


extension CDTask {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTask> {
        return NSFetchRequest<CDTask>(entityName: "CDTask")
    }

    @NSManaged public var essentiality: Int16
    @NSManaged public var isSessionTask: Bool
    @NSManaged public var lastCompleted: Date?
    @NSManaged public var maxDuration: Int32
    @NSManaged public var minDuration: Int32
    @NSManaged public var nextDueDate: Date?
    @NSManaged public var prepTime: Int16
    @NSManaged public var repetitionInterval: Int32
    @NSManaged public var taskName: String?
    @NSManaged public var uuid: UUID?
    @NSManaged public var shouldTrackAverageTime: Bool
    @NSManaged public var isChecklistTask: Bool
    @NSManaged public var checklistItems: NSObject?
    @NSManaged public var routineRelations: NSSet?
    @NSManaged public var completionTimes: NSSet?

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

// MARK: Generated accessors for completionTimes
extension CDTask {
    
    @objc(addCompletionTimesObject:)
    @NSManaged public func addToCompletionTimes(_ value: CDTaskCompletionTime)
    
    @objc(removeCompletionTimesObject:)
    @NSManaged public func removeFromCompletionTimes(_ value: CDTaskCompletionTime)
    
    @objc(addCompletionTimes:)
    @NSManaged public func addToCompletionTimes(_ values: NSSet)
    
    @objc(removeCompletionTimes:)
    @NSManaged public func removeFromCompletionTimes(_ values: NSSet)
}

extension CDTask : Identifiable {

}

// MARK: - Computed Properties
extension CDTask {
    /// Calculates the average completion time from the stored completion times
    var averageCompletionTime: TimeInterval? {
        guard let completionTimes = completionTimes as? Set<CDTaskCompletionTime>,
              !completionTimes.isEmpty else { return nil }
        
        let totalTime = completionTimes.reduce(0.0) { $0 + $1.completionTime }
        return totalTime / Double(completionTimes.count)
    }
}
