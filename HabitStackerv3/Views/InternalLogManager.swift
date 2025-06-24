// InternalLogManager.swift
import Foundation
import OSLog
import UIKit

struct TimeBlockDate: Hashable {
    let date: Date
    let block: TimeBlock
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(Calendar.current.startOfDay(for: date))
        hasher.combine(block.rawValue)
    }
    
    static func == (lhs: TimeBlockDate, rhs: TimeBlockDate) -> Bool {
        return Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) && lhs.block == rhs.block
    }
}

final class InternalLogManager: ObservableObject {
    static let shared = InternalLogManager()
    private let queue = DispatchQueue(label: "com.app.InternalLogManager", qos: .utility)
    private let logger = AppLogger(subsystem: "com.app.InternalLogManager", category: "LogStorage", logsInternally: false)
    
    @Published private(set) var sessions: [LogSession] = []
    @Published private(set) var currentSession: LogSession
    @Published private(set) var crashReportsLog: String = "" // Added for crash reports
    
    private let fileManager = FileManager.default
    private let maxSessionsPerTimeBlock = 100
    private var lastSaveTime: Date = Date()
    private let saveBatchInterval: TimeInterval = 30  // Save every 30 seconds
    
    // MARK: - File URLs
    private var documentsDirectoryURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var logsFolderURL: URL {
        let url = documentsDirectoryURL.appendingPathComponent("logs")
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var crashReportsFileURL: URL {
        documentsDirectoryURL.appendingPathComponent("crash_reports.log")
    }
    
    private func sessionFileURL(for timeBlock: TimeBlock, date: Date) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        return logsFolderURL.appendingPathComponent("\(dateString)-\(timeBlock.rawValue).json")
    }

    // MARK: - Initialization
    private init() {
        // Ensure currentSession is initialized before calling methods that might use it.
        self.currentSession = LogSession()
        
        // Use the logger *before* loading starts, just for system console output
        self.logger.info("InternalLogManager initializing...")
        
        loadSessions() // Load historical sessions first
        loadCrashReports() // Load existing crash reports
        setupNotificationObservers()
        
        // Start periodic save timer
        Timer.scheduledTimer(withTimeInterval: saveBatchInterval, repeats: true) { [weak self] _ in
            // Use optional chaining and self for logger call inside closure
            self?.logger.debug("Periodic save timer fired.")
            self?.saveIfNeeded()
        }
        
        // Log initialization completion to system console ONLY
        self.logger.info("InternalLogManager initialization complete. Current session ID: \(self.currentSession.id)")
    }
    
    func log(_ level: LogLevel, _ message: String, context: String, error: Error? = nil) {
        // Log to console that we received a log request (optional, good for debugging)
        // Use the internal logger instance for console output only.
        // Note: Avoid calling self.logger.debug here as it could cause recursion/deadlock
        print("[InternalLogManager] Received log request: [\(level.rawValue)] \(message)")
        
        queue.async { // Perform internal logging logic asynchronously
            let now = Date()
            var sessionChanged = false
            
            // Check if we need to start a new session based on time block
            // This needs careful synchronization if currentSession can be accessed from multiple threads
            // Accessing currentSession here within the queue should be safe
            if TimeBlock.from(date: now) != self.currentSession.timeBlock {
                // Log session change to console
                print("[InternalLogManager] Time block changed. Ending old session, starting new.")
                self.endCurrentSessionUnsafe(endTime: now) // Call unsafe version since we're already in the queue
                // Update currentSession safely within the queue
                self.currentSession = LogSession(startTime: now)
                sessionChanged = true
                print("[InternalLogManager] New Time Block Session Started. ID: \(self.currentSession.id)")
            }
            
            let record = LogRecord(
                level: level,
                message: message,
                context: context,
                error: error
            )
            
            // Capture the session ID we intend to log to
            let targetSessionID = self.currentSession.id
            
            // Append to the *current* session's records on the main thread
            DispatchQueue.main.async { // Dispatch UI-related update
                if self.currentSession.id == targetSessionID {
                    self.currentSession.records.append(record)
                    // Log appending completion
                    print("[InternalLogManager] Appended record ID \(record.id) to session \(targetSessionID) on main thread. New count: \(self.currentSession.records.count)")
                } else {
                    print("[InternalLogManager] Session changed between queue processing and main thread dispatch for record ID \(record.id). Appending to new session \(self.currentSession.id).")
                    // Append to the *new* current session instead
                    self.currentSession.records.append(record)
                    print("[InternalLogManager] Appended record ID \(record.id) to NEW session \(self.currentSession.id) on main thread. New count: \(self.currentSession.records.count)")
                }
            }
            
            // Trigger save if critical, batch interval reached, or if the session just changed
            if sessionChanged || level == .error || level == .fatal ||
               now.timeIntervalSince(self.lastSaveTime) >= self.saveBatchInterval {
                print("[InternalLogManager] Triggering saveIfNeeded (Reason: sessionChanged=\(sessionChanged), level=\(level.rawValue), interval=\(now.timeIntervalSince(self.lastSaveTime))s)")
                self.saveIfNeeded()
            }
        }
    }
    
    private func saveIfNeeded() {
        queue.async {
            var sessionToSave: LogSession?
            DispatchQueue.main.sync { // Safely access currentSession from main thread
                if !self.currentSession.records.isEmpty {
                    sessionToSave = self.currentSession
                }
            }
            
            // Only proceed if there are historical sessions or the current session has records
            guard !self.sessions.isEmpty || sessionToSave != nil else {
                // self.logger.debug("SaveIfNeeded: No sessions to save.") // Keep commented or remove if too noisy
                return
            }

            var allSessionsToConsider = self.sessions
            if let current = sessionToSave {
                allSessionsToConsider.append(current)
            }

            guard !allSessionsToConsider.isEmpty else {
                // self.logger.debug("SaveIfNeeded: All sessions considered are empty.") // Keep commented or remove
                return
            }

            let groupedSessions = Dictionary(grouping: allSessionsToConsider) { session in
                TimeBlockDate(date: session.startTime, block: session.timeBlock)
            }
            
            self.logger.info("[saveIfNeeded] Preparing to save \(allSessionsToConsider.count) session(s) across \(groupedSessions.count) file(s). Current session ID: \(sessionToSave?.id.uuidString ?? "None")")
            
            for (blockDate, sessionsInBlock) in groupedSessions {
                let fileURL = self.sessionFileURL(for: blockDate.block, date: blockDate.date)
                let trimmedSessions = Array(sessionsInBlock.sorted { $0.startTime > $1.startTime }.prefix(self.maxSessionsPerTimeBlock))
                
                // --- Add detailed logging before write --- 
                self.logger.debug("[saveIfNeeded] Attempting to save \(trimmedSessions.count) session(s) to file: \(fileURL.lastPathComponent)")
                let sessionIDs = trimmedSessions.map { $0.id.uuidString }.joined(separator: ", ")
                self.logger.debug("[saveIfNeeded] Session IDs for \(fileURL.lastPathComponent): [\(sessionIDs)]")
                // --- End detailed logging --- 
                
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = .prettyPrinted // Make JSON readable for debugging
                    let data = try encoder.encode(trimmedSessions)
                    try data.write(to: fileURL, options: .atomicWrite)
                    self.logger.info("[saveIfNeeded] Successfully saved \(trimmedSessions.count) session(s) to \(fileURL.lastPathComponent)") // Changed from debug to info
                } catch {
                    // Ensure the error log includes the specific file URL
                    self.logger.error("[saveIfNeeded] FAILED to save sessions to \(fileURL.lastPathComponent)", error: error)
                    // Log the encoding error specifically if it's an encoding error
                    if let encodingError = error as? EncodingError {
                        self.logger.error("[saveIfNeeded] Encoding Error Details: \(encodingError)")
                    }
                }
            }
            
            self.lastSaveTime = Date()
        }
    }
    
    private func cleanOldSessions() {
        queue.async {
            let calendar = Calendar.current
            // Keep logs for the last 7 days
            guard let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date()) else {
                self.logger.error("Failed to calculate cutoff date for cleaning old sessions.")
                return
            }
            
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(at: self.logsFolderURL, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
                self.logger.error("Failed to create enumerator for logs folder.")
                return
            }
            
            var removedCount = 0
            while let url = enumerator.nextObject() as? URL {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
                    // Skip directories and check creation date
                    if !(resourceValues.isDirectory ?? false),
                       let creationDate = resourceValues.creationDate,
                       creationDate < cutoffDate {
                        try fileManager.removeItem(at: url)
                        self.logger.info("Removed old log file: \(url.lastPathComponent)")
                        removedCount += 1
                    }
                } catch {
                    self.logger.error("Error processing or removing old log file \(url.lastPathComponent)", error: error)
                }
            }
            if removedCount > 0 {
                self.logger.info("Finished cleaning old log files. Removed \(removedCount) file(s).")
            } else {
                self.logger.debug("No old log files found to clean.")
            }
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func applicationWillTerminate() {
        logger.info("Application Will Terminate. Ending current session.")
        endCurrentSession(endTime: Date()) // Pass the current time as end time
    }
    
    @objc private func applicationDidEnterBackground() {
        logger.info("Application Did Enter Background. Ending current session.")
        endCurrentSession(endTime: Date()) // Pass the current time as end time
    }
    
    private func endCurrentSession(endTime: Date) {
        // 1. Capture the session to be ended safely using the queue.
        var sessionToEnd: LogSession?
        queue.sync { // Use sync to ensure session is captured and reset atomically
            sessionToEnd = endCurrentSessionUnsafe(endTime: endTime)
        }

        // 2. If a session was actually ended, trigger a save.
        if let endedSession = sessionToEnd {
            logger.debug("Session \(endedSession.id) ended. Triggering save.")
            saveIfNeeded()
        }
    }
    
    // Unsafe version that should only be called when already on the queue
    private func endCurrentSessionUnsafe(endTime: Date) -> LogSession? {
        var sessionToEnd: LogSession?
        
        // Only end if the current session has records
        if !self.currentSession.records.isEmpty {
            sessionToEnd = self.currentSession
            sessionToEnd?.endTime = endTime // Set the end time
            
            // Add the ended session to the historical list *before* resetting currentSession
            if let ended = sessionToEnd {
                DispatchQueue.main.async {
                    self.sessions.append(ended)
                    // Optionally notify UI about session list update here
                }
            }
        } else {
            print("[InternalLogManager] Attempted to end an empty session. Skipping.")
        }
        
        // Reset the 'live' currentSession immediately *after* handling the old one.
        // Start the new session immediately after the old one ends.
        self.currentSession = LogSession(startTime: endTime)
        print("[InternalLogManager] Ended session \(sessionToEnd?.id.uuidString ?? "N/A"). Started new session \(self.currentSession.id)")
        
        return sessionToEnd
    }
    
    private func startNewSessionIfNeeded() {
        let currentBlock = TimeBlock.from(date: Date())
        if currentSession.timeBlock != currentBlock {
            endCurrentSession(endTime: Date())
            currentSession = LogSession()
        }
    }
    
    func logCrash(exception: NSException) {
        let crashRecord = LogRecord(
            level: .fatal,
            message: "App crashed: \(exception.name.rawValue)",
            context: exception.callStackSymbols.joined(separator: "\n"),
            error: nil
        )
        
        queue.sync {
            currentSession.records.append(crashRecord)
            endCurrentSession(endTime: Date())
        }
    }
    
    private func loadSessions() {
        queue.sync { // Use sync to ensure loading completes before app continues fully
            let calendar = Calendar.current
            // Load logs from the last 2 days (today and yesterday) for potential crash context
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else {
                logger.error("Failed to calculate yesterday's date for loading sessions.")
                return
            }
            
            let today = Date()
            let datesToLoad = [yesterday, today]
            var loadedSessions: [LogSession] = []
            var fileCount = 0
            var sessionCount = 0

            logger.info("Loading sessions for dates: \(datesToLoad.map { $0.description(with: .current) })")

            for date in datesToLoad {
                for timeBlock in TimeBlock.allCases {
                    let fileURL = self.sessionFileURL(for: timeBlock, date: date)
                    guard fileManager.fileExists(atPath: fileURL.path) else { continue }
                    
                    fileCount += 1
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let sessionsFromFile = try decoder.decode([LogSession].self, from: data)
                        loadedSessions.append(contentsOf: sessionsFromFile)
                        sessionCount += sessionsFromFile.count
                        self.logger.debug("Successfully loaded \(sessionsFromFile.count) sessions from \(fileURL.lastPathComponent)")
                    } catch {
                        // Log detailed error but continue to the next file
                        self.logger.error("Failed to load/decode \(fileURL.lastPathComponent): \(error.localizedDescription)")
                        // Optionally log the full error object for more detail:
                        // self.logger.error("Full decoding error for \(fileURL.lastPathComponent): \(error)")
                    }
                }
            }
            
            // Update the @Published property on the main thread
            DispatchQueue.main.async {
                 // Sort sessions by start time, newest first
                self.sessions = loadedSessions.sorted { $0.startTime > $1.startTime }
                 self.logger.info("Finished loading sessions. Found \(sessionCount) sessions in \(fileCount) file(s). Current session count: \(self.sessions.count)")
            }
        }
    }
    
    private func saveCrashReportsLog() {
        queue.async {
            let logData = Data(self.crashReportsLog.utf8)
            do {
                try logData.write(to: self.crashReportsFileURL, options: .atomicWrite)
                self.logger.info("Successfully saved crash reports log.")
            } catch {
                self.logger.error("Failed to save crash reports log", error: error)
            }
        }
    }

    private func loadCrashReports() {
        queue.async { // Can run async, doesn't block startup critical path
            var loadedLog = ""
            if self.fileManager.fileExists(atPath: self.crashReportsFileURL.path) {
                do {
                    loadedLog = try String(contentsOf: self.crashReportsFileURL, encoding: .utf8)
                     self.logger.info("Successfully loaded existing crash reports log.")
                } catch {
                     self.logger.error("Failed to load crash reports log", error: error)
                }
            } else {
                 self.logger.info("No existing crash reports log file found.")
            }
            
            // Update the @Published property on the main thread
            DispatchQueue.main.async {
                self.crashReportsLog = loadedLog
            }
        }
    }

    // MARK: - Crash Reporting
    
    /// Generates a crash report containing logs from the 5 minutes before the last app restart.
    func generateAndAppendCrashReport() {
        // Add log statement HERE, before the queue dispatch
        self.logger.info("[generateAndAppendCrashReport] Function entered.")
        
        queue.async { // Perform heavy lifting off the main thread
            self.logger.info("[generateAndAppendCrashReport] Inside queue.async block.") // Renamed for clarity
            
            // 1. Determine the 'crash time' - use the start time of the current session.
            // Accessing currentSession.startTime is safe as it's set within the queue.
            let restartTime = self.currentSession.startTime
            self.logger.debug("Crash report based on restart time: \(restartTime)")

            // 2. Get relevant sessions directly, avoiding nested queue sync.
            // Access historical sessions (self.sessions) directly as we are on the queue.
            let historicalSessions = self.sessions
            
            // Get the current session state carefully.
            var currentSessionSnapshot: LogSession? = nil
            DispatchQueue.main.sync { // Sync with main thread ONLY to get current records.
                if !self.currentSession.records.isEmpty {
                    // Create a copy to avoid holding onto the main thread object longer than needed.
                    currentSessionSnapshot = LogSession(
                        id: self.currentSession.id,
                        startTime: self.currentSession.startTime,
                        endTime: self.currentSession.endTime, // May be nil
                        records: self.currentSession.records // Get snapshot of records
                    )
                }
            }

            // Combine historical and the snapshot of the current session.
            var sessionsToCheck = historicalSessions
            if let current = currentSessionSnapshot {
                sessionsToCheck.append(current)
            }
            
            // 3. Flatten all log records from relevant sessions
            let allRecords = sessionsToCheck.flatMap { $0.records }.sorted { $0.timestamp < $1.timestamp } // Sort oldest to newest
            
            // 4. Find the latest log timestamp *before* the restart time
            guard let lastLogBeforeRestart = allRecords.last(where: { $0.timestamp < restartTime }) else {
                self.logger.warning("Could not find any log messages before the app restart time (\(restartTime)). Cannot generate crash report based on prior logs.")
                // Append a specific entry to the crash log explaining the situation
                let reportHeader = "Crash Report Generation Info (\(Date()))"
                let reportContent = """
                No log entries found recorded *before* the app restart time of \(restartTime).
                This could mean the app was freshly installed, logs were cleared, 
                previous session files failed to load (check console logs), or the crash happened very soon after launch.
                """
                self.appendCrashReportEntry(header: reportHeader, content: reportContent)
                return // Stop further processing as there are no relevant logs
            }
            let effectiveCrashTime = lastLogBeforeRestart.timestamp
            self.logger.debug("Effective crash time (last log before restart): \(effectiveCrashTime)")

            // 5. Calculate the 5-minute window start time
            let fiveMinutesAgo = effectiveCrashTime.addingTimeInterval(-5 * 60) // 5 minutes * 60 seconds/minute
            self.logger.debug("Calculating logs between \(fiveMinutesAgo) and \(effectiveCrashTime)")

            // 6. Filter logs within that window
            let crashWindowLogs = allRecords.filter { $0.timestamp >= fiveMinutesAgo && $0.timestamp <= effectiveCrashTime }

            if crashWindowLogs.isEmpty {
                self.logger.warning("No logs found within the 5-minute window before the crash [\(fiveMinutesAgo) - \(effectiveCrashTime)].")
                self.appendCrashReportEntry(header: "Crash Report Warning (\(Date()))", content: "No log entries found in the 5-minute window before the effective crash time: \(effectiveCrashTime).")
                return
            }

            // 7. Format the report
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            let reportHeader = "Crash Report Generated: \(dateFormatter.string(from: Date()))\nRestart Time: \(dateFormatter.string(from: restartTime))\nEffective Crash Time (Last Log): \(dateFormatter.string(from: effectiveCrashTime))\nLog Window: [\(dateFormatter.string(from: fiveMinutesAgo)) to \(dateFormatter.string(from: effectiveCrashTime))]\nLog Count: \(crashWindowLogs.count)"
            
            let reportContent = crashWindowLogs.map { $0.formattedString }.joined(separator: "\n")
            
            // 8. Append to the master log
            self.appendCrashReportEntry(header: reportHeader, content: reportContent)
            self.logger.info("Successfully generated and appended crash report with \(crashWindowLogs.count) entries.")
        }
    }

    // Helper to append content to the crashReportsLog and save
    private func appendCrashReportEntry(header: String, content: String) {
        let entrySeparator = "\n========================================\n\n"
        let newEntry = "\(header)\n--- Logs ---\n\(content)"
        
        DispatchQueue.main.async {
            // Prepend the new report to the existing log
            if self.crashReportsLog.isEmpty {
                self.crashReportsLog = newEntry
            } else {
                self.crashReportsLog = newEntry + entrySeparator + self.crashReportsLog
            }
            // Trigger save for the updated crash log
            self.saveCrashReportsLog()
        }
    }

    /// Retrieves the content of the master crash report log.
    func getCrashReportsLog() -> String {
        // Access the @Published property safely (usually from main thread or ensure thread safety)
        // Since it's @Published, direct access is often okay from MainActor contexts (like SwiftUI views)
        // If accessed from background, dispatch to main or use a lock/queue.
        // Let's assume access from Main thread for simplicity here.
        return crashReportsLog
    }

    /// Clears the master crash report log file and in-memory variable.
    func clearCrashReportsLog() {
        queue.async {
            // Clear in-memory log on main thread
            DispatchQueue.main.async {
                self.crashReportsLog = ""
                 self.logger.info("Cleared in-memory crash reports log.")
            }
            
            // Delete the file from disk
            do {
                if self.fileManager.fileExists(atPath: self.crashReportsFileURL.path) {
                    try self.fileManager.removeItem(at: self.crashReportsFileURL)
                     self.logger.info("Successfully deleted crash reports log file.")
                } else {
                     self.logger.info("Crash reports log file not found, nothing to delete.")
                }
            } catch {
                 self.logger.error("Failed to delete crash reports log file", error: error)
            }
        }
    }
}

extension InternalLogManager {
    /// Gets all log sessions, including the current session. **Must be called from the main thread.**
    func getAllSessions() -> [LogSession] {
        dispatchPrecondition(condition: .onQueue(.main))
        self.logger.debug("[getAllSessions] Called.") // Log entry
        
        var allSessions: [LogSession] = []
        allSessions = self.sessions
        let historicalCount = allSessions.count
        
        var currentSessionRecordsCount = 0
        if !self.currentSession.records.isEmpty {
            currentSessionRecordsCount = self.currentSession.records.count
            allSessions.append(self.currentSession)
        }
        
        // Log what was found
        self.logger.debug("[getAllSessions] Found \(historicalCount) historical session(s). Current session has \(currentSessionRecordsCount) record(s). Total sessions returned: \(allSessions.count)")

        return allSessions.sorted { $0.startTime > $1.startTime }
    }
    
    /// Clears all stored logs
    func clearAllLogs() {
        queue.async {
            // Clear in-memory sessions on the main thread
            DispatchQueue.main.async {
                self.sessions.removeAll()
                // Optionally reset currentSession here if needed, but endCurrentSession logic might handle this
                // self.currentSession = LogSession() // Be cautious if you reset this without ending
                 self.logger.info("Cleared in-memory log sessions.")
            }
            
            // Delete the log files from disk
            do {
                let fileURLs = try self.fileManager.contentsOfDirectory(at: self.logsFolderURL, includingPropertiesForKeys: nil)
                for fileURL in fileURLs where fileURL.pathExtension == "json" {
                    try self.fileManager.removeItem(at: fileURL)
                     self.logger.debug("Removed log file: \(fileURL.lastPathComponent)")
                }
                 self.logger.info("Successfully cleared all log session files.")
            } catch {
                 self.logger.error("Failed to clear log session files", error: error)
            }
        }
    }
    
    /// Gets formatted logs for a session
    func getFormattedSessionLogs(_ session: LogSession) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var output = """
        Session Start: \(dateFormatter.string(from: session.startTime))
        Session End: \(session.endTime.map { dateFormatter.string(from: $0) } ?? "Active")
        Time Block: \(session.timeBlock.timeRange)
        Duration: \(formatDuration(session.duration))
        Number of Logs: \(session.records.count)
        
        --- Logs ---
        
        """
        
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        for record in session.records {
            output += """
            [\(dateFormatter.string(from: record.timestamp))] [\(record.level.rawValue.uppercased())]
            Context: \(record.context)
            Message: \(record.message)
            \(record.error != nil ? "Error: \(record.error!)\n" : "")
            ---
            
            """
        }
        
        return output
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let remainingSeconds = seconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, remainingMinutes, remainingSeconds)
        } else {
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }
    }
}
