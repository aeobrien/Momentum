// HabitStackerv3/SyncService.swift
// Sync service for pushing Momentum data to the LifePlanner unified system.

import Foundation
import CoreData
import Combine

// MARK: - LifePlanner Payload Models

struct LPMomentumTask: Codable {
    let source_id: String
    let name: String
    let essentiality: Int
    let min_duration_seconds: Int
    let max_duration_seconds: Int
    let prep_time_seconds: Int
    let repetition_interval_days: Int
    let is_session_task: Bool
    let is_checklist_task: Bool
    let checklist_items: [[String: AnyCodableValue]]?
    let last_completed: String? // ISO 8601
    let average_completion_time_seconds: Double?
}

struct LPMomentumRoutine: Codable {
    let source_id: String
    let name: String
    let total_completions: Int
    let average_completion_time_seconds: Double?
    let task_source_ids: [String]
}

struct LPMomentumCompletion: Codable {
    let task_source_id: String
    let completed_at: String // ISO 8601
    let duration_seconds: Double
}

struct LPMomentumPayload: Codable {
    let app_version: String
    let exported_at: String // ISO 8601
    let tasks: [LPMomentumTask]
    let routines: [LPMomentumRoutine]
    let recent_completions: [LPMomentumCompletion]
}

struct LPIngestionResult: Codable {
    let created: Int
    let updated: Int
    let conflicts: Int
    let archived: Int
}

/// Wrapper for encoding heterogeneous checklist item values.
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else { self = .string("") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        }
    }
}

// MARK: - Sync Service

class SyncService: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var lastSyncResult: String?
    @Published var isSyncing = false
    @Published var lastError: String?

    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // UserDefaults keys
    private static let serverURLKey = "lifeplanner_momentum_sync_server_url"
    private static let autoSyncKey = "lifeplanner_momentum_sync_auto_enabled"
    private static let lastSyncDateKey = "lifeplanner_momentum_sync_last_date"

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: Self.serverURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.serverURLKey) }
    }

    var autoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoSyncKey) }
    }

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        self.lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date
    }

    // MARK: - Payload Construction

    func buildPayload() -> LPMomentumPayload {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let now = iso8601Formatter.string(from: Date())

        // Fetch all tasks
        let taskRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        let cdTasks = (try? context.fetch(taskRequest)) ?? []

        var lpTasks: [LPMomentumTask] = []
        for task in cdTasks {
            guard let uuid = task.uuid else { continue }

            // Convert checklist items
            var checklistData: [[String: AnyCodableValue]]?
            if task.isChecklistTask, let items = task.checklistItems as? [ChecklistItem] {
                checklistData = items.sorted(by: { $0.order < $1.order }).map { item in
                    [
                        "id": .string(item.id.uuidString),
                        "title": .string(item.title),
                        "isCompleted": .bool(item.isCompleted),
                        "order": .int(item.order),
                    ]
                }
            }

            lpTasks.append(LPMomentumTask(
                source_id: uuid.uuidString,
                name: task.taskName ?? "Unnamed",
                essentiality: Int(task.essentiality),
                min_duration_seconds: Int(task.minDuration),
                max_duration_seconds: Int(task.maxDuration),
                prep_time_seconds: Int(task.prepTime),
                repetition_interval_days: Int(task.repetitionInterval),
                is_session_task: task.isSessionTask,
                is_checklist_task: task.isChecklistTask,
                checklist_items: checklistData,
                last_completed: task.lastCompleted.map { iso8601Formatter.string(from: $0) },
                average_completion_time_seconds: task.averageCompletionTime
            ))
        }

        // Fetch all routines
        let routineRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        let cdRoutines = (try? context.fetch(routineRequest)) ?? []

        var lpRoutines: [LPMomentumRoutine] = []
        for routine in cdRoutines {
            guard let uuid = routine.uuid else { continue }

            // Get ordered task UUIDs via CDRoutineTask
            let relations = (routine.taskRelations as? Set<CDRoutineTask>) ?? []
            let orderedRelations = relations.sorted { $0.order < $1.order }
            let taskSourceIds = orderedRelations.compactMap { $0.task?.uuid?.uuidString }

            lpRoutines.append(LPMomentumRoutine(
                source_id: uuid.uuidString,
                name: routine.name ?? "Unnamed",
                total_completions: Int(routine.totalCompletions),
                average_completion_time_seconds: routine.averageCompletionTime > 0 ? routine.averageCompletionTime : nil,
                task_source_ids: taskSourceIds
            ))
        }

        // Fetch recent completions (last 7 days)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let completionRequest: NSFetchRequest<CDTaskCompletionTime> = CDTaskCompletionTime.fetchRequest()
        completionRequest.predicate = NSPredicate(format: "date >= %@", sevenDaysAgo as NSDate)
        let cdCompletions = (try? context.fetch(completionRequest)) ?? []

        var lpCompletions: [LPMomentumCompletion] = []
        for completion in cdCompletions {
            guard let taskUUID = completion.task?.uuid,
                  let date = completion.date else { continue }

            lpCompletions.append(LPMomentumCompletion(
                task_source_id: taskUUID.uuidString,
                completed_at: iso8601Formatter.string(from: date),
                duration_seconds: completion.completionTime
            ))
        }

        return LPMomentumPayload(
            app_version: appVersion,
            exported_at: now,
            tasks: lpTasks,
            routines: lpRoutines,
            recent_completions: lpCompletions
        )
    }

    // MARK: - Sync

    func sync() async {
        guard !serverURL.isEmpty else {
            await MainActor.run {
                self.lastError = "Server URL not configured"
            }
            return
        }

        let baseURL = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let url = URL(string: "\(baseURL)/ingest/momentum") else {
            await MainActor.run {
                self.lastError = "Invalid server URL"
            }
            return
        }

        await MainActor.run {
            self.isSyncing = true
            self.lastError = nil
        }

        let payload = buildPayload()

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(payload)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SyncError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "No body"
                throw SyncError.serverError(statusCode: httpResponse.statusCode, body: body)
            }

            let result = try JSONDecoder().decode(LPIngestionResult.self, from: data)
            let now = Date()

            await MainActor.run {
                self.lastSyncDate = now
                self.isSyncing = false
                self.lastSyncResult = "Created: \(result.created), Updated: \(result.updated)"
                UserDefaults.standard.set(now, forKey: Self.lastSyncDateKey)
            }

            print("SyncService: Momentum sync completed — created=\(result.created) updated=\(result.updated)")
        } catch {
            await MainActor.run {
                self.isSyncing = false
                self.lastError = error.localizedDescription
            }
            print("SyncService: Momentum sync failed — \(error)")
        }
    }

    // MARK: - Test Connection

    func testConnection() async -> Bool {
        guard !serverURL.isEmpty else {
            await MainActor.run { self.lastError = "Server URL not configured" }
            return false
        }

        let baseURL = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let url = URL(string: "\(baseURL)/health") else {
            await MainActor.run { self.lastError = "Invalid server URL" }
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { self.lastError = "Server returned non-200 status" }
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               status == "ok" {
                await MainActor.run { self.lastError = nil }
                return true
            }

            await MainActor.run { self.lastError = "Unexpected health response" }
            return false
        } catch {
            await MainActor.run { self.lastError = "Connection failed: \(error.localizedDescription)" }
            return false
        }
    }

    // MARK: - Auto-sync

    func autoSyncIfEnabled() {
        guard autoSyncEnabled, !serverURL.isEmpty else { return }
        Task {
            await sync()
        }
    }

    // MARK: - Error types

    enum SyncError: LocalizedError {
        case invalidResponse
        case serverError(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server"
            case .serverError(let code, let body):
                return "Server error (\(code)): \(body)"
            }
        }
    }
}
