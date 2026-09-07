//
//  CDTaskCompletionTime+CoreDataProperties.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 06/11/2024.
//
//

import Foundation
import CoreData


extension CDTaskCompletionTime {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTaskCompletionTime> {
        return NSFetchRequest<CDTaskCompletionTime>(entityName: "CDTaskCompletionTime")
    }

    @NSManaged public var completionTime: Double
    @NSManaged public var date: Date?
    @NSManaged public var index: Int16
    @NSManaged public var task: CDTask?

}

extension CDTaskCompletionTime : Identifiable {

}