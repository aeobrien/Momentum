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
    private let relayURL = URL(
        string: "https://aidans-mac-mini.tailc50104.ts.net/momentum/data"
    )!
    private let relayHealthURL = URL(
        string: "https://aidans-mac-mini.tailc50104.ts.net/momentum/health"
    )!
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
        probeRelayConnection()
    }

    /// Called whenever any NSManagedObjectContext saves. Triggers a debounced shared file write.
    @objc private func contextDidSave(_ notification: Notification) {
        // Use the viewContext to read the latest merged state
        let context = DataStoreManager.shared.viewContext
        saveCurrentState(context: context)
    }

    // MARK: - Reliable local copy

    private var localFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MomentumRelay", isDirectory: true)
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
        // Send the app data first. HealthKit can take a long time or wait on a
        // permission decision, and must never prevent tasks and routines from
        // reaching the relay.
        uploadAppSnapshot(context: context, retryAttempt: 0)

        // Follow with an enriched snapshot when the health reads finish.
        HealthKitReader.shared.fetchLast30Days { [weak self] healthDays in
            guard let self else { return }
            context.perform {
                do {
                    var sharedData = try self.buildSharedData(from: context)
                    sharedData.healthSummary = HealthSummary(
                        lastUpdated: Date(),
                        last30Days: healthDays
                    )
                    try self.persistAndUpload(sharedData)
                    self.logger.info("Saved and uploaded the HealthKit-enriched snapshot")
                } catch {
                    self.logger.error("Failed to save the HealthKit-enriched snapshot: \(error.localizedDescription)")
                    self.reportDiagnostic(stage: "health_export_failed", detail: error.localizedDescription)
                }
            }
        }
    }

    private func uploadAppSnapshot(context: NSManagedObjectContext, retryAttempt: Int) {
        context.perform { [weak self] in
            guard let self else { return }
            do {
                let sharedData = try self.buildSharedData(from: context)
                try self.persistAndUpload(sharedData)
                self.logger.info("Saved and uploaded the immediate app snapshot")
            } catch {
                self.logger.error("Failed to save the immediate app snapshot: \(error.localizedDescription)")
                self.reportDiagnostic(stage: "app_export_failed", detail: error.localizedDescription)
                if retryAttempt < 3 {
                    self.saveQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.uploadAppSnapshot(context: context, retryAttempt: retryAttempt + 1)
                    }
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
                averageCompletionTime: routine.averageCompletionTime.isFinite ? routine.averageCompletionTime : 0,
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
                        duration: completion.completionTime.isFinite ? completion.completionTime : 0
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

    // MARK: - Local persistence and private relay

    private func encode(_ data: MomentumSharedData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }

    private func persistAndUpload(_ sharedData: MomentumSharedData) throws {
        let jsonData = try encode(sharedData)
        // The phone-to-Mac feed is the primary output. A failure in the local
        // safety copy must not prevent the upload.
        uploadToRelay(jsonData)
        do {
            try writeLocalCopy(jsonData)
        } catch {
            logger.warning("Private relay upload started, but the local safety copy failed: \(error.localizedDescription)")
        }
    }

    private func probeRelayConnection() {
        var components = URLComponents(url: relayHealthURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "stage", value: "startup"),
            URLQueryItem(name: "build", value: "4"),
        ]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.setValue("startup", forHTTPHeaderField: "X-Momentum-Stage")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.logger.warning("Private relay startup check failed: \(error.localizedDescription)")
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            self?.logger.info("Private relay startup check returned HTTP \(status)")
        }.resume()
    }

    private func reportDiagnostic(stage: String, detail: String) {
        var components = URLComponents(url: relayHealthURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "stage", value: stage),
            URLQueryItem(name: "build", value: "4"),
            URLQueryItem(name: "detail", value: String(detail.prefix(240))),
        ]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request).resume()
    }

    private func writeLocalCopy(_ jsonData: Data) throws {
        guard let fileURL = localFileURL else {
            throw SharedDataStoreError.localStorageUnavailable
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try jsonData.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func uploadToRelay(_ jsonData: Data) {
        var request = URLRequest(url: relayURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        URLSession.shared.uploadTask(with: request, from: jsonData) { [weak self] _, response, error in
            if let error {
                self?.logger.warning("Private relay upload failed; the local copy will be retried: \(error.localizedDescription)")
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.logger.warning("Private relay upload returned HTTP \(status); the local copy will be retried")
                return
            }
            self?.logger.info("Private relay accepted the Momentum snapshot")
        }.resume()
    }
}

// MARK: - Errors

enum SharedDataStoreError: LocalizedError {
    case localStorageUnavailable
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .localStorageUnavailable:
            return "Local storage is not available for shared data."
        case .encodingFailed:
            return "Failed to encode shared data as JSON."
        case .writeFailed:
            return "Failed to write shared data locally."
        }
    }
}
