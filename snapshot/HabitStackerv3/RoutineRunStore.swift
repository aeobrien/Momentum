// HabitStackerv3/RoutineRunStore.swift
// Persistence for pending routine run data to be synced to LifePlanner.

import Foundation

// MARK: - Routine Run Data

struct LPRoutineRun: Codable {
    let routine_source_id: String
    let started_at: String        // ISO 8601
    let ended_at: String          // ISO 8601
    let scheduled_task_source_ids: [String]
    let completed_task_source_ids: [String]
    let skipped_task_source_ids: [String]
    let early_exit: Bool
}

// MARK: - Store

class RoutineRunStore {
    static let shared = RoutineRunStore()

    private static let key = "lifeplanner_pending_routine_runs"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private init() {}

    /// Append a new routine run to the pending list.
    func save(_ run: LPRoutineRun) {
        var runs = loadAll()
        runs.append(run)
        persist(runs)
    }

    /// Load all pending routine runs.
    func loadAll() -> [LPRoutineRun] {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else {
            return []
        }
        return (try? decoder.decode([LPRoutineRun].self, from: data)) ?? []
    }

    /// Clear all pending runs (call after successful sync).
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func persist(_ runs: [LPRoutineRun]) {
        if let data = try? encoder.encode(runs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
