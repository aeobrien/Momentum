import Foundation

struct BackupData: Codable {
    let version: String
    let createdDate: Date
    let deviceName: String
    let tasks: [BackupTask]
    let routines: [BackupRoutine]
    let routineTasks: [BackupRoutineTask]
    let taskCompletionTimes: [BackupTaskCompletionTime]
    let preferences: BackupPreferences
    
    static let currentVersion = "1.0"
}

struct BackupTask: Codable {
    let uuid: UUID
    let taskName: String
    let essentiality: Int16
    let isSessionTask: Bool
    let lastCompleted: Date?
    let nextDueDate: Date?
    let minDuration: Int32
    let maxDuration: Int32
    let repetitionInterval: Int32
    let shouldTrackAverageTime: Bool
    let isChecklistTask: Bool
    let checklistItems: [ChecklistItem]?
}

struct BackupRoutine: Codable {
    let uuid: UUID
    let name: String
    let createdOn: Date
    let lastUsed: Date?
    let averageCompletionTime: Double
    let totalCompletions: Int32
}

struct BackupRoutineTask: Codable {
    let routineID: UUID
    let taskID: UUID
    let order: Int32
}

struct BackupTaskCompletionTime: Codable {
    let taskID: UUID
    let completionTime: Double
    let date: Date
    let index: Int16
}

struct BackupPreferences: Codable {
    let activeRoutineID: String?
    let additionalPreferences: [String: String]
}