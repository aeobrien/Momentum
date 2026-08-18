import Foundation
import CoreData
import OSLog

extension CDTask {
    // Convert Core Data object to domain model
    func toDomainModel() -> CustomTask {
        return CustomTask(
            uuid: self.uuid?.uuidString ?? UUID().uuidString,
            taskName: self.taskName ?? "",
            essentiality: Int(self.essentiality),
            minDuration: Int(self.minDuration),
            maxDuration: Int(self.maxDuration),
            lastCompleted: lastCompleted.map { ISO8601DateFormatter.shared.string(from: $0) },
            repetitionInterval: Int(self.repetitionInterval),
            isSessionTask: self.isSessionTask,
            shouldTrackAverageTime: self.shouldTrackAverageTime,
            averageCompletionTime: self.averageCompletionTime,
            isChecklistTask: self.isChecklistTask,
            checklistItems: self.checklistItems as? [ChecklistItem],
            prepTime: Int(self.prepTime)
        )
    }
    
    // Update Core Data object from domain model with new UUID
    func update(from task: CustomTask, withNewUUID newUUID: String) {
        // NOTE: Using default logger temporarily as AppLogger might not be available here
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CDTaskUpdate")
        
        // Debug UUID handling
        logger.debug("Setting UUID for task '\(task.taskName, privacy: .public)': \(newUUID, privacy: .public)")
        if let uuid = UUID(uuidString: newUUID) {
            self.uuid = uuid
            logger.debug("Successfully created UUID object")
        } else {
            logger.error("Failed to create UUID from string: \(newUUID, privacy: .public)")
            self.uuid = UUID() // Fallback UUID
        }
        
        self.taskName = task.taskName
        self.essentiality = Int16(task.essentiality ?? 0)
        self.minDuration = Int32(task.minDuration)
        self.maxDuration = Int32(task.maxDuration)
        if let lastCompletedStr = task.lastCompleted {
            self.lastCompleted = ISO8601DateFormatter.shared.date(from: lastCompletedStr)
        }
        self.repetitionInterval = Int32(task.repetitionInterval ?? 0)
        
        self.isSessionTask = task.isSessionTask
        self.shouldTrackAverageTime = task.shouldTrackAverageTime
        self.isChecklistTask = task.isChecklistTask
        self.prepTime = Int16(task.prepTime)

        // Debug checklist items
        if let checklistItems = task.checklistItems {
            logger.debug("Setting \(checklistItems.count, privacy: .public) checklist items for task '\(task.taskName, privacy: .public)'")
            for (index, item) in checklistItems.enumerated() {
                logger.debug("  Checklist item \(index, privacy: .public): \(item.title, privacy: .public)")
            }
        }
        
        self.checklistItems = task.checklistItems as NSObject?
        
        // Verify the stored UUID
        logger.debug("Stored UUID: \(self.uuid?.uuidString ?? "nil", privacy: .public)")
    }
    
    // Update Core Data object from domain model (using original UUID)
    func updateCDTask(from task: CustomTask) {
        self.update(from: task, withNewUUID: task.uuid)
    }
    
    // MARK: - Computed Properties for Eligibility
    
    /// Determines if the task is eligible to be scheduled *right now*.
    var isEligibleNow: Bool {
        // Tasks without a next due date (don't repeat or never completed) are always eligible
        guard let dueDate = self.nextDueDate else {
            return true
        }

        let now = Date()
        let calendar = Calendar.current

        // For tasks with repetition intervals less than 24 hours,
        // they should only be eligible when actually due
        if self.repetitionInterval > 0 && self.repetitionInterval < 86400 {
            // Strict timing: eligible only if due time has passed
            return now >= dueDate
        }

        // For longer intervals (>= 24 hours) or daily reset tasks,
        // eligible from midnight of the due date
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDueDate = calendar.startOfDay(for: dueDate)

        // Eligible if the due date is on or before today
        return startOfDueDate <= startOfToday
    }
}


