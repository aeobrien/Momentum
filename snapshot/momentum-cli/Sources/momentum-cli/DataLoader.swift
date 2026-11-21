import Foundation
import Darwin

enum DataLoaderError: Error, CustomStringConvertible {
    case noDataFound
    case dataNotDownloaded
    case parseError(String)

    var description: String {
        switch self {
        case .noDataFound:
            return "No Momentum data found. Checked the private relay, local cache, shared file, and backup directory."
        case .dataNotDownloaded:
            return "Momentum data exists in iCloud but is not downloaded on this Mac. Open MomentumData.json in Finder to download it, then retry."
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
    static let cacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/momentum-cli")
    static let cacheFilePath = cacheDir.appendingPathComponent("MomentumData.json")
    static let defaultRelayURL = URL(
        string: "https://aidans-mac-mini.tailc50104.ts.net/momentum/data"
    )!
    static let maximumRelayBytes = 16 * 1024 * 1024

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
        var foundDatalessFile = false

        // The phone publishes to the private Tailscale relay. Read that first so
        // routine and HealthKit status no longer depend on iCloud downloading a file.
        if let relayData = fetchRelayData() {
            do {
                var parsed = try parseSharedFile(relayData)
                parsed.source = .relay
                saveCache(relayData)
                return parsed
            } catch {
                fputs("Warning: The private Momentum relay returned invalid data: \(error)\n", stderr)
            }
        }

        // Retain the old iCloud file as a fallback during the transition.
        if FileManager.default.fileExists(atPath: sharedFilePath.path) {
            if isDataless(sharedFilePath) {
                foundDatalessFile = true
                fputs("Warning: MomentumData.json is an iCloud placeholder, so it was not opened. Trying downloaded backups.\n", stderr)
            } else {
                do {
                    let data = try Data(contentsOf: sharedFilePath)
                    let parsed = try parseSharedFile(data)
                    saveCache(data)
                    return parsed
                } catch {
                    // Fall through to backup
                    fputs("Warning: Failed to read shared file, trying backups: \(error)\n", stderr)
                }
            }
        }

        var fallbacks: [MomentumData] = []

        // A successful shared-file read is cached locally. This keeps the CLI
        // useful if macOS later evicts the iCloud file again.
        if FileManager.default.fileExists(atPath: cacheFilePath.path) {
            do {
                let cachedData = try Data(contentsOf: cacheFilePath)
                var parsed = try parseSharedFile(cachedData)
                parsed.source = .cache
                fallbacks.append(parsed)
            } catch {
                fputs("Warning: Failed to read the local Momentum cache: \(error)\n", stderr)
            }
        }

        // Try the latest downloaded backup. Never open a dataless iCloud
        // placeholder because Data(contentsOf:) can wait indefinitely for it.
        for backupURL in findBackupsNewestFirst() {
            if isDataless(backupURL) {
                foundDatalessFile = true
                continue
            }
            do {
                let data = try Data(contentsOf: backupURL)
                fallbacks.append(try parseBackupFile(data, url: backupURL))
                break
            } catch {
                fputs("Warning: Failed to read backup \(backupURL.lastPathComponent): \(error)\n", stderr)
            }
        }

        if let newestFallback = fallbacks.max(by: {
            ($0.sourceDate ?? .distantPast) < ($1.sourceDate ?? .distantPast)
        }) {
            fputs("Warning: Using the newest local Momentum fallback (\(newestFallback.source.rawValue)).\n", stderr)
            return newestFallback
        }

        if foundDatalessFile { throw DataLoaderError.dataNotDownloaded }
        throw DataLoaderError.noDataFound
    }

    static func findBackupsNewestFirst() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let backups = contents.filter { $0.pathExtension == "momentumbackup" }
        return backups
            .compactMap { url -> (URL, Date)? in
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let date = attrs[.modificationDate] as? Date else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func findLatestBackup() -> URL? {
        findBackupsNewestFirst().first
    }

    static func isDataless(_ url: URL) -> Bool {
        var fileStatus = stat()
        let result = url.path.withCString { path in
            Darwin.lstat(path, &fileStatus)
        }
        guard result == 0 else { return false }
        return (fileStatus.st_flags & UInt32(SF_DATALESS)) != 0
    }

    static func saveCache(_ data: Data) {
        do {
            try FileManager.default.createDirectory(
                at: cacheDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: cacheFilePath, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: cacheFilePath.path
            )
        } catch {
            fputs("Warning: Could not update the local Momentum cache: \(error)\n", stderr)
        }
    }

    static func relayURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if environment["MOMENTUM_DISABLE_RELAY"] == "1" { return nil }
        if let configured = environment["MOMENTUM_RELAY_URL"], !configured.isEmpty {
            return URL(string: configured)
        }
        return defaultRelayURL
    }

    static func fetchRelayData() -> Data? {
        guard let url = relayURL() else { return nil }

        // The command is macOS-only. Use the operating system's curl process:
        // it already shares the same DNS and Tailscale path as the rest of the
        // laptop and, unlike a blocked main-thread URLSession, cannot deadlock
        // an ArgumentParser command while waiting for its completion callback.
        let process = Process()
        let downloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("momentum-relay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: downloadURL) }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--fail", "--silent", "--show-error",
            "--max-time", "4",
            "--max-filesize", String(maximumRelayBytes),
            "--output", downloadURL.path,
            url.absoluteString,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("Warning: Could not start the private Momentum relay reader; trying local fallbacks.\n", stderr)
            return nil
        }

        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: downloadURL),
              !data.isEmpty,
              data.count <= maximumRelayBytes else {
            fputs("Warning: The private Momentum relay is unavailable; trying local fallbacks.\n", stderr)
            return nil
        }
        return data
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

        let healthSummary = shared.healthSummary.map { summary in
            HealthSummary(
                lastUpdated: parseDate(summary.lastUpdated),
                last30Days: summary.last30Days.compactMap { day in
                    guard let date = parseDate(day.date) else { return nil }
                    return HealthDaySummary(
                        date: date,
                        meditationMinutes: day.meditationMinutes,
                        meditationSessions: day.meditationSessions,
                        steps: day.steps,
                        walkingDistanceKm: day.walkingDistanceKm,
                        activeEnergyKcal: day.activeEnergyKcal,
                        exerciseMinutes: day.exerciseMinutes,
                        sleepMinutes: day.sleepMinutes
                    )
                }
            )
        }

        return MomentumData(
            tasks: tasks,
            routines: routines,
            completionHistory: completions,
            healthSummary: healthSummary,
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
            healthSummary: nil,
            source: .backup,
            sourceDate: parseDate(backup.createdDate)
        )
    }

    /// Load raw JSON data for export
    static func loadRawJSON() throws -> Data {
        if let data = fetchRelayData() {
            saveCache(data)
            return data
        }
        if FileManager.default.fileExists(atPath: sharedFilePath.path) {
            if !isDataless(sharedFilePath) {
                return try Data(contentsOf: sharedFilePath)
            }
        }
        for backupURL in findBackupsNewestFirst() where !isDataless(backupURL) {
            if let data = try? Data(contentsOf: backupURL) {
                return data
            }
        }
        if FileManager.default.fileExists(atPath: cacheFilePath.path),
           let data = try? Data(contentsOf: cacheFilePath) {
            return data
        }
        if FileManager.default.fileExists(atPath: sharedFilePath.path) || !findBackupsNewestFirst().isEmpty {
            throw DataLoaderError.dataNotDownloaded
        }
        throw DataLoaderError.noDataFound
    }
}
