import Foundation

enum DataLoaderError: Error, CustomStringConvertible {
    case noDataFound
    case parseError(String)

    var description: String {
        switch self {
        case .noDataFound:
            return "No Momentum data found. Checked shared file and backup directory."
        case .parseError(let msg):
            return "Failed to parse data: \(msg)"
        }
    }
}

struct DataLoader {
    static let iCloudBase = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~AOTondra~Momentum/Documents")

    static let sharedFilePath = iCloudBase.appendingPathComponent("MomentumData.json")
    static let backupDir = iCloudBase.appendingPathComponent("MomentumBackups")

    static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Also handle fractional seconds
    static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        return iso8601Formatter.date(from: string)
            ?? iso8601FractionalFormatter.date(from: string)
    }

    static func load() throws -> MomentumData {
        // Try shared file first
        if FileManager.default.fileExists(atPath: sharedFilePath.path) {
            do {
                let data = try Data(contentsOf: sharedFilePath)
                return try parseSharedFile(data)
            } catch {
                // Fall through to backup
                fputs("Warning: Failed to read shared file, trying backups: \(error)\n", stderr)
            }
        }

        // Try latest backup
        if let backupURL = findLatestBackup() {
            let data = try Data(contentsOf: backupURL)
            return try parseBackupFile(data, url: backupURL)
        }

        throw DataLoaderError.noDataFound
    }

    static func findLatestBackup() -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let backups = contents.filter { $0.pathExtension == "momentumbackup" }
        return backups
            .compactMap { url -> (URL, Date)? in
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let date = attrs[.modificationDate] as? Date else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    // MARK: - Parse Shared File

    static func parseSharedFile(_ data: Data) throws -> MomentumData {
        let shared = try JSONDecoder().decode(SharedFile.self, from: data)

        let tasks = shared.tasks.map { t in
            Task(
                uuid: t.uuid,
                taskName: t.taskName,
                essentiality: t.essentiality,
                isSessionTask: t.isSessionTask,
                isChecklistTask: t.isChecklistTask,
                lastCompleted: parseDate(t.lastCompleted),
                nextDueDate: parseDate(t.nextDueDate),
                minDuration: t.minDuration,
                maxDuration: t.maxDuration,
                repetitionInterval: t.repetitionInterval,
                checklistItems: (t.checklistItems ?? []).map {
                    ChecklistItem(id: $0.id, title: $0.title, isCompleted: $0.isCompleted, order: $0.order)
                }
            )
        }

        let routines = shared.routines.map { r in
            Routine(
                uuid: r.uuid,
                name: r.name,
                taskUUIDs: r.taskUUIDs,
                averageCompletionTime: r.averageCompletionTime,
                totalCompletions: r.totalCompletions,
                lastUsed: parseDate(r.lastUsed)
            )
        }

        let completions = shared.completionHistory.map { c in
            CompletionEntry(
                taskUUID: c.taskUUID,
                date: parseDate(c.date) ?? Date.distantPast,
                duration: c.duration
            )
        }

        return MomentumData(
            tasks: tasks,
            routines: routines,
            completionHistory: completions,
            source: .shared,
            sourceDate: parseDate(shared.lastModified)
        )
    }

    // MARK: - Parse Backup File

    static func parseBackupFile(_ data: Data, url: URL) throws -> MomentumData {
        let backup = try JSONDecoder().decode(BackupFile.self, from: data)

        let tasks = backup.tasks.map { t in
            Task(
                uuid: t.uuid,
                taskName: t.taskName,
                essentiality: t.essentiality,
                isSessionTask: t.isSessionTask,
                isChecklistTask: t.isChecklistTask,
                lastCompleted: parseDate(t.lastCompleted),
                nextDueDate: parseDate(t.nextDueDate),
                minDuration: t.minDuration,
                maxDuration: t.maxDuration,
                repetitionInterval: t.repetitionInterval,
                checklistItems: []
            )
        }

        // Build routine task map: routineID -> [(order, taskID)]
        var routineTaskMap: [String: [(Int, String)]] = [:]
        for rt in backup.routineTasks {
            routineTaskMap[rt.routineID, default: []].append((rt.order, rt.taskID))
        }

        let routines = backup.routines.map { r in
            let orderedTaskIDs = (routineTaskMap[r.uuid] ?? [])
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
            return Routine(
                uuid: r.uuid,
                name: r.name,
                taskUUIDs: orderedTaskIDs,
                averageCompletionTime: r.averageCompletionTime,
                totalCompletions: r.totalCompletions,
                lastUsed: parseDate(r.lastUsed)
            )
        }

        let completions = backup.taskCompletionTimes.map { c in
            CompletionEntry(
                taskUUID: c.taskID,
                date: parseDate(c.date) ?? Date.distantPast,
                duration: c.completionTime
            )
        }

        return MomentumData(
            tasks: tasks,
            routines: routines,
            completionHistory: completions,
            source: .backup,
            sourceDate: parseDate(backup.createdDate)
        )
    }

    /// Load raw JSON data for export
    static func loadRawJSON() throws -> Data {
        if FileManager.default.fileExists(atPath: sharedFilePath.path) {
            return try Data(contentsOf: sharedFilePath)
        }
        if let backupURL = findLatestBackup() {
            return try Data(contentsOf: backupURL)
        }
        throw DataLoaderError.noDataFound
    }
}
