import Foundation
import CoreData

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
            repetitionInterval: Int(self.repetitionInterval)
        )
    }
    
    // Update Core Data object from domain model with new UUID
    func update(from task: CustomTask, withNewUUID newUUID: String) {
        let logger = AppLogger.create(subsystem: "com.app.CDTask", category: "Update")
        
        // Debug UUID handling
        logger.debug("Setting UUID for task '\(task.taskName)': \(newUUID)")
        if let uuid = UUID(uuidString: newUUID) {
            self.uuid = uuid
            logger.debug("Successfully created UUID object")
        } else {
            logger.error("Failed to create UUID from string: \(newUUID)")
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
        
        // Verify the stored UUID
        logger.debug("Stored UUID: \(self.uuid?.uuidString ?? "nil")")
    }
    
    // Update Core Data object from domain model (using original UUID)
    func update(from task: CustomTask) {
        self.update(from: task, withNewUUID: task.uuid)
    }
}