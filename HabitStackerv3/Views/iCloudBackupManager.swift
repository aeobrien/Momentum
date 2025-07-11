import Foundation
import CoreData
import UIKit

class iCloudBackupManager: ObservableObject {
    static let shared = iCloudBackupManager()
    
    @Published var isBackupInProgress = false
    @Published var isRestoreInProgress = false
    @Published var lastBackupDate: Date?
    @Published var availableBackups: [BackupInfo] = []
    @Published var iCloudAvailable = false
    
    private let containerURL: URL?
    private let backupDirectoryName = "MomentumBackups"
    private let fileExtension = "momentumbackup"
    private let logger = AppLogger.create(subsystem: "com.AOTondra.Momentum", category: "Backup")
    
    struct BackupInfo: Identifiable {
        let id = UUID()
        let url: URL
        let createdDate: Date
        let deviceName: String
        let fileSize: Int64
    }
    
    init() {
        containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)
        checkiCloudAvailability()
        
        if let lastBackup = UserDefaults.standard.object(forKey: "lastiCloudBackupDate") as? Date {
            lastBackupDate = lastBackup
        }
        
        Task {
            await loadAvailableBackups()
        }
    }
    
    private func checkiCloudAvailability() {
        if let token = FileManager.default.ubiquityIdentityToken {
            iCloudAvailable = true
            logger.info("iCloud is available")
        } else {
            iCloudAvailable = false
            logger.warning("iCloud is not available")
        }
    }
    
    private var backupDirectory: URL? {
        guard let containerURL = containerURL else { return nil }
        return containerURL.appendingPathComponent("Documents").appendingPathComponent(backupDirectoryName)
    }
    
    func createBackup(context: NSManagedObjectContext) async throws {
        guard iCloudAvailable else {
            throw BackupError.iCloudNotAvailable
        }
        
        await MainActor.run {
            isBackupInProgress = true
        }
        
        defer {
            Task { @MainActor in
                isBackupInProgress = false
            }
        }
        
        logger.info("Starting backup creation")
        
        let backupData = try await createBackupData(from: context)
        
        let fileName = "Momentum_Backup_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")).\(fileExtension)"
        
        guard let backupDir = backupDirectory else {
            throw BackupError.invalidDirectory
        }
        
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        let fileURL = backupDir.appendingPathComponent(fileName)
        let document = MomentumBackupDocument(fileURL: fileURL)
        document.backupData = backupData
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: fileURL, for: .forCreating) { success in
                if success {
                    self.logger.info("Backup saved successfully to: \(fileName)")
                    continuation.resume()
                } else {
                    self.logger.error("Failed to save backup")
                    continuation.resume(throwing: BackupError.saveFailed)
                }
            }
        }
        
        await MainActor.run {
            lastBackupDate = Date()
            UserDefaults.standard.set(lastBackupDate, forKey: "lastiCloudBackupDate")
        }
        
        await loadAvailableBackups()
    }
    
    private func createBackupData(from context: NSManagedObjectContext) async throws -> BackupData {
        try await context.perform {
            let taskFetch = CDTask.fetchRequest()
            let tasks = try context.fetch(taskFetch)
            
            let routineFetch = CDRoutine.fetchRequest()
            let routines = try context.fetch(routineFetch)
            
            let backupTasks = tasks.compactMap { task -> BackupTask? in
                guard let uuid = task.uuid else {
                    self.logger.warning("Skipping task without UUID: \(task.taskName ?? "Unnamed")")
                    return nil
                }
                return BackupTask(
                    uuid: uuid,
                    taskName: task.taskName ?? "Unnamed Task",
                    essentiality: task.essentiality,
                    isSessionTask: task.isSessionTask,
                    lastCompleted: task.lastCompleted,
                    nextDueDate: task.nextDueDate,
                    minDuration: task.minDuration,
                    maxDuration: task.maxDuration,
                    repetitionInterval: task.repetitionInterval,
                    shouldTrackAverageTime: task.shouldTrackAverageTime
                )
            }
            
            let backupRoutines = routines.compactMap { routine -> BackupRoutine? in
                guard let uuid = routine.uuid,
                      let name = routine.name,
                      let createdOn = routine.createdOn else {
                    self.logger.warning("Skipping routine without required fields: \(routine.name ?? "Unnamed")")
                    return nil
                }
                return BackupRoutine(
                    uuid: uuid,
                    name: name,
                    createdOn: createdOn,
                    lastUsed: routine.lastUsed,
                    averageCompletionTime: routine.averageCompletionTime,
                    totalCompletions: routine.totalCompletions
                )
            }
            
            var backupRoutineTasks: [BackupRoutineTask] = []
            var backupCompletionTimes: [BackupTaskCompletionTime] = []
            
            for routine in routines {
                guard let routineUUID = routine.uuid else { continue }
                if let taskRelations = routine.taskRelations?.allObjects as? [CDRoutineTask] {
                    for relation in taskRelations {
                        if let task = relation.task,
                           let taskUUID = task.uuid {
                            backupRoutineTasks.append(BackupRoutineTask(
                                routineID: routineUUID,
                                taskID: taskUUID,
                                order: relation.order
                            ))
                        }
                    }
                }
            }
            
            for task in tasks {
                guard let taskUUID = task.uuid else { continue }
                if let completionTimes = task.completionTimes?.allObjects as? [CDTaskCompletionTime] {
                    for completion in completionTimes {
                        guard let date = completion.date else {
                            self.logger.warning("Skipping completion time without date for task: \(task.taskName ?? "Unnamed")")
                            continue
                        }
                        backupCompletionTimes.append(BackupTaskCompletionTime(
                            taskID: taskUUID,
                            completionTime: completion.completionTime,
                            date: date,
                            index: completion.index
                        ))
                    }
                }
            }
            
            let preferences = BackupPreferences(
                activeRoutineID: UserDefaults.standard.string(forKey: "activeRoutineID"),
                additionalPreferences: [:]
            )
            
            return BackupData(
                version: BackupData.currentVersion,
                createdDate: Date(),
                deviceName: UIDevice.current.name,
                tasks: backupTasks,
                routines: backupRoutines,
                routineTasks: backupRoutineTasks,
                taskCompletionTimes: backupCompletionTimes,
                preferences: preferences
            )
        }
    }
    
    func restoreFromBackup(at url: URL, context: NSManagedObjectContext) async throws {
        guard iCloudAvailable else {
            throw BackupError.iCloudNotAvailable
        }
        
        await MainActor.run {
            isRestoreInProgress = true
        }
        
        defer {
            Task { @MainActor in
                isRestoreInProgress = false
            }
        }
        
        logger.info("Starting restore from backup: \(url.lastPathComponent)")
        
        let document = MomentumBackupDocument(fileURL: url)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.open { success in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BackupError.openFailed)
                }
            }
        }
        
        guard let backupData = document.backupData else {
            throw BackupError.invalidData
        }
        
        try await restoreData(backupData, to: context)
        
        document.close(completionHandler: nil)
        
        logger.info("Restore completed successfully")
    }
    
    private func restoreData(_ backupData: BackupData, to context: NSManagedObjectContext) async throws {
        try await context.perform {
            let deleteTasksRequest = NSBatchDeleteRequest(fetchRequest: CDTask.fetchRequest())
            let deleteRoutinesRequest = NSBatchDeleteRequest(fetchRequest: CDRoutine.fetchRequest())
            
            try context.execute(deleteTasksRequest)
            try context.execute(deleteRoutinesRequest)
            
            var taskMapping: [UUID: CDTask] = [:]
            var routineMapping: [UUID: CDRoutine] = [:]
            
            for backupTask in backupData.tasks {
                let task = CDTask(context: context)
                task.uuid = backupTask.uuid
                task.taskName = backupTask.taskName
                task.essentiality = backupTask.essentiality
                task.isSessionTask = backupTask.isSessionTask
                task.lastCompleted = backupTask.lastCompleted
                task.nextDueDate = backupTask.nextDueDate
                task.minDuration = backupTask.minDuration
                task.maxDuration = backupTask.maxDuration
                task.repetitionInterval = backupTask.repetitionInterval
                task.shouldTrackAverageTime = backupTask.shouldTrackAverageTime
                taskMapping[backupTask.uuid] = task
            }
            
            for backupRoutine in backupData.routines {
                let routine = CDRoutine(context: context)
                routine.uuid = backupRoutine.uuid
                routine.name = backupRoutine.name
                routine.createdOn = backupRoutine.createdOn
                routine.lastUsed = backupRoutine.lastUsed
                routine.averageCompletionTime = backupRoutine.averageCompletionTime
                routine.totalCompletions = backupRoutine.totalCompletions
                routineMapping[backupRoutine.uuid] = routine
            }
            
            for backupRelation in backupData.routineTasks {
                if let routine = routineMapping[backupRelation.routineID],
                   let task = taskMapping[backupRelation.taskID] {
                    let relation = CDRoutineTask(context: context)
                    relation.routine = routine
                    relation.task = task
                    relation.order = backupRelation.order
                }
            }
            
            for backupCompletion in backupData.taskCompletionTimes {
                if let task = taskMapping[backupCompletion.taskID] {
                    let completion = CDTaskCompletionTime(context: context)
                    completion.task = task
                    completion.completionTime = backupCompletion.completionTime
                    completion.date = backupCompletion.date
                    completion.index = backupCompletion.index
                }
            }
            
            try context.save()
            
            if let activeRoutineID = backupData.preferences.activeRoutineID {
                UserDefaults.standard.set(activeRoutineID, forKey: "activeRoutineID")
            }
        }
    }
    
    func loadAvailableBackups() async {
        guard let backupDir = backupDirectory else { return }
        
        do {
            let fileManager = FileManager.default
            
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: backupDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                await MainActor.run {
                    availableBackups = []
                }
                return
            }
            
            let urls = try fileManager.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
            
            var backups: [BackupInfo] = []
            
            for url in urls where url.pathExtension == fileExtension {
                let document = MomentumBackupDocument(fileURL: url)
                
                let opened = await withCheckedContinuation { continuation in
                    document.open { success in
                        continuation.resume(returning: success)
                    }
                }
                
                if opened, let data = document.backupData {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    
                    backups.append(BackupInfo(
                        url: url,
                        createdDate: data.createdDate,
                        deviceName: data.deviceName,
                        fileSize: fileSize
                    ))
                    
                    document.close(completionHandler: nil)
                }
            }
            
            await MainActor.run {
                availableBackups = backups.sorted { $0.createdDate > $1.createdDate }
            }
            
        } catch {
            logger.error("Error loading backups: \(error)")
        }
    }
    
    func deleteBackup(at url: URL) async throws {
        try FileManager.default.removeItem(at: url)
        await loadAvailableBackups()
    }
    
    func scheduleAutomaticBackup() {
        let lastBackup = lastBackupDate ?? Date.distantPast
        let hoursSinceLastBackup = Date().timeIntervalSince(lastBackup) / 3600
        
        if hoursSinceLastBackup >= 24 {
            Task {
                do {
                    let context = DataStoreManager.shared.viewContext
                    try await createBackup(context: context)
                } catch {
                    self.logger.error("Automatic backup failed: \(error)")
                }
            }
        }
    }
}

enum BackupError: LocalizedError {
    case iCloudNotAvailable
    case invalidDirectory
    case saveFailed
    case openFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud is not available. Please check your iCloud settings."
        case .invalidDirectory:
            return "Could not access iCloud backup directory."
        case .saveFailed:
            return "Failed to save backup to iCloud."
        case .openFailed:
            return "Failed to open backup file."
        case .invalidData:
            return "Backup file contains invalid data."
        }
    }
}