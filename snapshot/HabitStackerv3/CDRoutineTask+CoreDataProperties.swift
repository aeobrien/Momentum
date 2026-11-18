//
//  CDRoutineTask+CoreDataProperties.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 06/11/2024.
//
//

import Foundation
import CoreData


extension CDRoutineTask {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDRoutineTask> {
        return NSFetchRequest<CDRoutineTask>(entityName: "CDRoutineTask")
    }

    @NSManaged public var order: Int32
    @NSManaged public var routine: CDRoutine?
    @NSManaged public var task: CDTask?

}

extension CDRoutineTask : Identifiable {

}
