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

    /// One place a snapshot can be delivered to.
    ///
    /// There are two now. The Mac Mini was the only one, and the Chief of Staff
    /// that reads this data runs on the laptop — so every reading had to cross
    /// two machines, and when this was checked the Mini had been offline for
    /// three days and the newest health day on the laptop was a week old.
    /// Delivering to both means a Mini that is off no longer stops a reading
    /// arriving. It does not make the phone's own connection unnecessary.
    private struct RelayDestination {
        let name: String
        let dataURL: URL
        let healthURL: URL
    }

    /// Each destination is delivered to on its own. One being unreachable does
    /// not hold up or cancel the other, and each reports its own outcome, so a
    /// log says which machine took the snapshot rather than just "uploaded".
    ///
    /// Recovery from a missed delivery is the next delivery, not a stored queue:
    /// the relay at each end keeps only the newest snapshot it has been given and
    /// refuses anything older, so the following hourly wake supersedes whatever
    /// was missed. A destination that is down for a day costs freshness while it
    /// is down and nothing afterwards.
    private let destinations: [RelayDestination] = [
        RelayDestination(
            name: "mac-mini",
            dataURL: URL(string: "https://aidans-mac-mini.tailc50104.ts.net/momentum/data")!,
            healthURL: URL(string: "https://aidans-mac-mini.tailc50104.ts.net/momentum/health")!
        ),
        RelayDestination(
            name: "laptop",
            dataURL: URL(string: "https://aidans-laptop-1.tailc50104.ts.net/momentum/data")!,
            healthURL: URL(string: "https://aidans-laptop-1.tailc50104.ts.net/momentum/health")!
        ),
    ]
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

    /// Rebuild the health summary from HealthKit and deliver it, for a launch
    /// that iOS made in the background because health data changed.
    ///
    /// This is separate from `performSave` on purpose. `performSave` sends the
    /// app's tasks and routines first and the health-enriched snapshot second,
    /// which is right when Aidan has just changed something in the app. On a
    /// background health wake nothing in the app has changed, so sending the app
    /// snapshot as well would spend a tight background budget uploading the same
    /// tasks twice.
    ///
    /// It re-reads HealthKit rather than serialising whatever is in memory:
    /// on a background launch there is nothing in memory yet, and the whole
    /// point of the wake is the readings that have just appeared.
    func saveHealthSnapshotFromBackground() {
        let context = DataStoreManager.shared.viewContext
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
                    self.logger.info("Delivered a health snapshot from a background wake")
                } catch {
                    self.logger.error("A background health wake could not be delivered: \(error.localizedDescription)")
                    self.reportDiagnostic(stage: "background_health_failed", detail: error.localizedDescription)
                }
            }
        }
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
        for destination in destinations {
            var components = URLComponents(url: destination.healthURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "stage", value: "startup"),
                URLQueryItem(name: "build", value: "4"),
            ]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            request.setValue("startup", forHTTPHeaderField: "X-Momentum-Stage")
            let name = destination.name
            URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                if let error {
                    self?.logger.warning("Startup check for the \(name) relay failed: \(error.localizedDescription)")
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.logger.info("Startup check for the \(name) relay returned HTTP \(status)")
            }.resume()
        }
    }

    private func reportDiagnostic(stage: String, detail: String) {
        for destination in destinations {
            var components = URLComponents(url: destination.healthURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "stage", value: stage),
                URLQueryItem(name: "build", value: "4"),
                URLQueryItem(name: "detail", value: String(detail.prefix(240))),
            ]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            URLSession.shared.dataTask(with: request).resume()
        }
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
        for destination in destinations {
            upload(jsonData, to: destination)
        }
    }

    private func upload(_ jsonData: Data, to destination: RelayDestination) {
        var request = URLRequest(url: destination.dataURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let name = destination.name
        URLSession.shared.uploadTask(with: request, from: jsonData) { [weak self] _, response, error in
            if let error {
                self?.logger.warning("Upload to the \(name) relay failed; the next delivery supersedes it: \(error.localizedDescription)")
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.logger.warning("The \(name) relay returned HTTP \(status); the next delivery supersedes it")
                return
            }
            self?.logger.info("The \(name) relay accepted the Momentum snapshot")
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
