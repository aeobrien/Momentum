import Foundation
import CoreData

// MARK: - Shared Data Models

struct MomentumSharedData: Codable {
    var tasks: [SharedTask]
    var routines: [SharedRoutine]
    var completionHistory: [SharedCompletionEntry]
    var healthSummary: HealthSummary?
    var lastModified: Date
    var lastModifiedBy: String  // "app"
}

struct SharedTask: Codable {
    var uuid: UUID
    var taskName: String
    var essentiality: Int
    var isSessionTask: Bool
    var lastCompleted: Date?
    var nextDueDate: Date?
    var minDuration: Int
    var maxDuration: Int
    var repetitionInterval: Int
    var isChecklistTask: Bool
    var checklistItems: [SharedChecklistItem]
}

struct SharedChecklistItem: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var order: Int
}

struct SharedRoutine: Codable {
    var uuid: UUID
    var name: String
    var taskUUIDs: [UUID]  // ordered
    var averageCompletionTime: Double
    var totalCompletions: Int
    var lastUsed: Date?
}

struct SharedCompletionEntry: Codable {
    var taskUUID: UUID
    var date: Date
    var duration: Double
}

// MARK: - SharedDataStore

final class SharedDataStore {
    static let shared = SharedDataStore()

    private let fileName = "MomentumData.json"
    private let logger = AppLogger.create(subsystem: "com.AOTondra.Momentum", category: "SharedDataStore")

    /// Debounce timer to avoid excessive writes
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.AOTondra.Momentum.SharedDataStore", qos: .utility)

    private init() {
        // Observe all Core Data saves to trigger shared file updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
    }

    /// Called whenever any NSManagedObjectContext saves. Triggers a debounced shared file write.
    @objc private func contextDidSave(_ notification: Notification) {
        // Use the viewContext to read the latest merged state
        let context = DataStoreManager.shared.viewContext
        saveCurrentState(context: context)
    }

    // MARK: - iCloud Container URL

    private var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    private var sharedFileURL: URL? {
        guard let containerURL = containerURL else {
            logger.warning("iCloud container not available")
            return nil
        }
        return containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(fileName)
    }

    // MARK: - Save Current State

    /// Saves the current Core Data state to the shared JSON file.
    /// Debounced to avoid excessive writes when multiple changes happen in quick succession.
    func saveCurrentState(context: NSManagedObjectContext) {
        // Cancel any pending save
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave(context: context)
        }
        pendingSaveWorkItem = workItem

        // Debounce: wait 2 seconds before actually writing
        saveQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    /// Performs the actual save without debouncing. Use for immediate saves (e.g. app backgrounding).
    func saveCurrentStateImmediately(context: NSManagedObjectContext) {
        pendingSaveWorkItem?.cancel()
        performSave(context: context)
    }

    private func performSave(context: NSManagedObjectContext) {
        // Fetch health data first (async), then build and write the full JSON
        HealthKitReader.shared.fetchLast30Days { [weak self] healthDays in
            guard let self = self else { return }

            let healthSummary = HealthSummary(
                lastUpdated: Date(),
                last30Days: healthDays
            )

            context.perform {
                do {
                    var sharedData = try self.buildSharedData(from: context)
                    sharedData.healthSummary = healthSummary
                    try self.writeToiCloud(sharedData)
                    self.logger.info("Successfully wrote shared data to iCloud (with health summary)")
                } catch {
                    self.logger.error("Failed to save shared data: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Build Shared Data from Core Data

    private func buildSharedData(from context: NSManagedObjectContext) throws -> MomentumSharedData {
        // Fetch all tasks
        let taskFetch: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        let cdTasks = try context.fetch(taskFetch)

        // Fetch all routines
        let routineFetch: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        let cdRoutines = try context.fetch(routineFetch)

        // Map tasks
        let sharedTasks: [SharedTask] = cdTasks.compactMap { task in
            guard let uuid = task.uuid else { return nil }

            var sharedChecklistItems: [SharedChecklistItem] = []
            if let items = task.checklistItems as? [ChecklistItem] {
                sharedChecklistItems = items.map { item in
                    SharedChecklistItem(
                        id: item.id,
                        title: item.title,
                        isCompleted: item.isCompleted,
                        order: item.order
                    )
                }
            }

            return SharedTask(
                uuid: uuid,
                taskName: task.taskName ?? "Unnamed Task",
                essentiality: Int(task.essentiality),
                isSessionTask: task.isSessionTask,
                lastCompleted: task.lastCompleted,
                nextDueDate: task.nextDueDate,
                minDuration: Int(task.minDuration),
                maxDuration: Int(task.maxDuration),
                repetitionInterval: Int(task.repetitionInterval),
                isChecklistTask: task.isChecklistTask,
                checklistItems: sharedChecklistItems
            )
        }

        // Map routines
        let sharedRoutines: [SharedRoutine] = cdRoutines.compactMap { routine in
            guard let uuid = routine.uuid, let name = routine.name else { return nil }

            // Get ordered task UUIDs
            var taskUUIDs: [UUID] = []
            if let relations = routine.taskRelations?.allObjects as? [CDRoutineTask] {
                let sorted = relations.sorted { $0.order < $1.order }
                taskUUIDs = sorted.compactMap { $0.task?.uuid }
            }

            return SharedRoutine(
                uuid: uuid,
                name: name,
                taskUUIDs: taskUUIDs,
                averageCompletionTime: routine.averageCompletionTime,
                totalCompletions: Int(routine.totalCompletions),
                lastUsed: routine.lastUsed
            )
        }

        // Map completion history
        var completionHistory: [SharedCompletionEntry] = []
        for task in cdTasks {
            guard let taskUUID = task.uuid else { continue }
            if let completions = task.completionTimes?.allObjects as? [CDTaskCompletionTime] {
                for completion in completions {
                    guard let date = completion.date else { continue }
                    completionHistory.append(SharedCompletionEntry(
                        taskUUID: taskUUID,
                        date: date,
                        duration: completion.completionTime
                    ))
                }
            }
        }

        return MomentumSharedData(
            tasks: sharedTasks,
            routines: sharedRoutines,
            completionHistory: completionHistory,
            lastModified: Date(),
            lastModifiedBy: "app"
        )
    }

    // MARK: - Write to iCloud

    private func writeToiCloud(_ data: MomentumSharedData) throws {
        guard let fileURL = sharedFileURL else {
            throw SharedDataStoreError.iCloudNotAvailable
        }

        // Ensure Documents directory exists
        let documentsDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)

        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)

        // Write with NSFileCoordinator for safe iCloud access
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { writtenURL in
            do {
                try jsonData.write(to: writtenURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = writeError {
            throw error
        }
    }
}

// MARK: - Errors

enum SharedDataStoreError: LocalizedError {
    case iCloudNotAvailable
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud container is not available for shared data."
        case .encodingFailed:
            return "Failed to encode shared data as JSON."
        case .writeFailed:
            return "Failed to write shared data to iCloud."
        }
    }
}
