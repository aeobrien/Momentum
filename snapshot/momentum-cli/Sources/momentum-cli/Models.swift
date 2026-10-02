import Foundation

// MARK: - Unified Internal Model

struct MomentumData {
    var tasks: [Task]
    var routines: [Routine]
    var completionHistory: [CompletionEntry]
    var source: DataSource
    var sourceDate: Date?

    enum DataSource: String {
        case shared = "MomentumData.json"
        case backup = "Backup"
    }
}

struct Task {
    var uuid: String
    var taskName: String
    var essentiality: Int
    var isSessionTask: Bool
    var isChecklistTask: Bool
    var lastCompleted: Date?
    var nextDueDate: Date?
    var minDuration: Int  // seconds in shared, raw int in backup
    var maxDuration: Int
    var repetitionInterval: Int  // seconds
    var checklistItems: [ChecklistItem]
}

struct ChecklistItem {
    var id: String
    var title: String
    var isCompleted: Bool
    var order: Int
}

struct Routine {
    var uuid: String
    var name: String
    var taskUUIDs: [String]  // ordered
    var averageCompletionTime: Double
    var totalCompletions: Int
    var lastUsed: Date?
}

struct CompletionEntry {
    var taskUUID: String
    var date: Date
    var duration: Double  // seconds
}

// MARK: - Backup File JSON Models

struct BackupFile: Codable {
    var version: String?
    var createdDate: String?
    var deviceName: String?
    var tasks: [BackupTask]
    var routines: [BackupRoutine]
    var routineTasks: [BackupRoutineTask]
    var taskCompletionTimes: [BackupCompletionTime]
}

struct BackupTask: Codable {
    var uuid: String
    var taskName: String
    var essentiality: Int
    var isSessionTask: Bool
    var isChecklistTask: Bool
    var lastCompleted: String?
    var nextDueDate: String?
    var minDuration: Int
    var maxDuration: Int
    var repetitionInterval: Int
    var shouldTrackAverageTime: Bool?
}

struct BackupRoutine: Codable {
    var uuid: String
    var name: String
    var averageCompletionTime: Double
    var totalCompletions: Int
    var lastUsed: String?
    var createdOn: String?
}

struct BackupRoutineTask: Codable {
    var routineID: String
    var taskID: String
    var order: Int
}

struct BackupCompletionTime: Codable {
    var taskID: String
    var date: String
    var completionTime: Double
    var index: Int?
}

// MARK: - Shared File JSON Models

struct SharedFile: Codable {
    var tasks: [SharedFileTask]
    var routines: [SharedFileRoutine]
    var completionHistory: [SharedFileCompletion]
    var lastModified: String
    var lastModifiedBy: String
}

struct SharedFileTask: Codable {
    var uuid: String
    var taskName: String
    var essentiality: Int
    var isSessionTask: Bool
    var isChecklistTask: Bool
    var lastCompleted: String?
    var nextDueDate: String?
    var minDuration: Int
    var maxDuration: Int
    var repetitionInterval: Int
    var checklistItems: [SharedFileChecklistItem]?
}

struct SharedFileChecklistItem: Codable {
    var id: String
    var title: String
    var isCompleted: Bool
    var order: Int
}

struct SharedFileRoutine: Codable {
    var uuid: String
    var name: String
    var taskUUIDs: [String]
    var averageCompletionTime: Double
    var totalCompletions: Int
    var lastUsed: String?
}

struct SharedFileCompletion: Codable {
    var taskUUID: String
    var date: String
    var duration: Double
}
