import SwiftUI
import CoreData


struct SettingsView: View {
    
    // Remove the default 22-pt padding above the first section header
    init() {
        if #available(iOS 15, *) {
            UITableView.appearance().sectionHeaderTopPadding = 0
        }
    }
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var backupManager = iCloudBackupManager.shared
    @StateObject private var dataStoreManager = DataStoreManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    
    @State private var showLogsView = false
    @State private var showResetConfirmation = false
    @State private var showExportSuccess = false
    @State private var showBackupRestoreView = false
    @State private var showRoutineExportSuccess = false
    @State private var showRoutineImportAlert = false
    @State private var importedRoutinesCount = 0
    @State private var showRestartAlert = false
    
    private let logger = AppLogger.create(subsystem: "com.app.SettingsView", category: "UI")
    
    var body: some View {
        List {
            // MARK: Data Management
            Section(header: Text("Data Management")) {
                    
                    Button {
                        showBackupRestoreView = true
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up.down")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Backup & Restore")
                            Spacer()
                            if let lastBackup = backupManager.lastBackupDate {
                                Text(lastBackup, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Button(action: exportAllData) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Export Tasks as JSON")
                            Spacer()
                        }
                    }
                    
                    Button(action: exportRoutines) {
                        HStack {
                            Image(systemName: "star.square.on.square")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Export Routines as JSON")
                            Spacer()
                        }
                    }
                    
                    Button(action: importRoutinesFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Import Routines from Clipboard")
                            Spacer()
                        }
                    }
                    
                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundColor(.orange)
                                .frame(width: 30)
                            Text("Reset All Completion Dates")
                            Spacer()
                        }
                    }
                }
                
                // MARK: Scheduling
                Section(header: Text("Scheduling")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Schedule Buffer Time")
                                    .font(.body)
                                
                                HStack {
                                    Text("\(settingsManager.scheduleBufferMinutes) minutes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                            
                            Spacer()
                            
                            Stepper("", value: $settingsManager.scheduleBufferMinutes, in: 0...30, step: 5)
                                .labelsHidden()
                        }
                        
                        Text("This buffer time is automatically subtracted from your available time when scheduling routines. It helps ensure you finish earlier than expected and provides wiggle room if tasks run longer than planned.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 38)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    // Background Notification Interval
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Background Reminder Interval")
                                    .font(.body)
                                
                                HStack {
                                    Text("\(settingsManager.backgroundNotificationIntervalSeconds) seconds")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                            
                            Spacer()
                            
                            Stepper("", value: $settingsManager.backgroundNotificationIntervalSeconds, in: 30...300, step: 30)
                                .labelsHidden()
                        }
                        
                        Text("When running a routine and the app is in the background, you'll receive periodic reminders at this interval to help you stay on track.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 38)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: Import Instructions
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Import Instructions")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text("You can use the buttons above to import tasks or routines directly from your clipboard. The app accepts data in JSON format (see examples below) or copied spreadsheet tables from Excel, Numbers, or Google Sheets. This makes it easy to bulk add or edit your tasks and routines outside the app.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Link("Download spreadsheet template", destination: URL(string: "https://google.com")!)
                            .font(.footnote)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Task JSON Structure:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text("""
                            [{
                              "taskName": "Breakfast",
                              "minDuration": 25,
                              "maxDuration": 25,
                              "essentiality": 3,
                              "repetitionInterval": 0,
                              "uuid": "2FA3751C-AEBF-471C-8D53-90263258913F"
                            }]
                            """)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Routine JSON Structure:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text("""
                            [{
                              "name": "Catch Up",
                              "taskUUIDs": ["..."],
                              "id": "9CA34E08-7BCB-4B5D-9EC0-5B147CAC062A"
                            }]
                            """)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // MARK: Diagnostics
                Section(header: Text("Diagnostics")) {
                    Button { showLogsView = true } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("View Logs")
                            Spacer()
                        }
                    }
                    
                }
                
                // MARK: Developer Options
                Section(header: Text("Developer Options")) {
                    Toggle(isOn: Binding(
                        get: { dataStoreManager.isTestingModeEnabled },
                        set: { _ in 
                            dataStoreManager.toggleTestingMode()
                            showRestartAlert = true
                        }
                    )) {
                        HStack {
                            Image(systemName: "testtube.2")
                                .foregroundColor(.purple)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text("Testing Mode")
                                Text("Use a separate test database")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // MARK: About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        
        // MARK: Sheets
        .sheet(isPresented: $showLogsView)            { LogsView() }
        .sheet(isPresented: $showBackupRestoreView)   { BackupRestoreView() }
        
        // MARK: Alerts
        .alert("Tasks Exported", isPresented: $showExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("All tasks have been exported to clipboard as JSON")
        }
        .alert("Reset Completion Dates?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset All", role: .destructive) { resetAllCompletionDates() }
        } message: {
            Text("This will remove the \"Last Completed\" date from all tasks. This action cannot be undone.")
        }
        .alert("Routines Exported", isPresented: $showRoutineExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("All routines have been exported to clipboard as JSON")
        }
        .alert("Routines Imported", isPresented: $showRoutineImportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(importedRoutinesCount) new routine(s) have been imported successfully")
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please restart the app for the testing mode change to take effect. This ensures your data is properly separated.")
        }
    }
    
    // MARK: - Data actions (unchanged from your original)
    
    private func exportAllData() {
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)]
        
        do {
            let tasks = try viewContext.fetch(fetchRequest)
            let domainTasks = tasks.map { $0.toDomainModel() }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let jsonData = try encoder.encode(domainTasks)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                UIPasteboard.general.string = jsonString
                showExportSuccess = true
                logger.info("Successfully exported \(tasks.count) tasks to clipboard")
            }
        } catch {
            logger.error("Failed to export tasks", error: error)
        }
    }
    
    private func resetAllCompletionDates() {
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        
        do {
            let tasks = try viewContext.fetch(fetchRequest)
            for task in tasks { task.lastCompleted = nil }
            try viewContext.save()
            logger.info("Reset completion dates for \(tasks.count) tasks")
        } catch {
            logger.error("Failed to reset completion dates", error: error)
        }
    }
    
    private func exportRoutines() {
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDRoutine.name, ascending: true)]
        
        do {
            let cdRoutines = try viewContext.fetch(fetchRequest)
            let routines = cdRoutines.map { $0.toDomainModel() }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let jsonData = try encoder.encode(routines)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                UIPasteboard.general.string = jsonString
                showRoutineExportSuccess = true
                logger.info("Successfully exported \(routines.count) routines to clipboard")
            }
        } catch {
            logger.error("Failed to export routines", error: error)
        }
    }
    
    private func importRoutinesFromClipboard() {
        guard let jsonString = UIPasteboard.general.string,
              let jsonData  = jsonString.data(using: .utf8) else {
            logger.warning("No valid JSON text found in clipboard")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let routines = try decoder.decode([Routine].self, from: jsonData)
            
            importedRoutinesCount = 0
            for routine in routines {
                let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "name == %@", routine.name)
                
                if try viewContext.count(for: fetchRequest) == 0 {
                    let cdRoutine = CDRoutine(context: viewContext)
                    cdRoutine.update(from: routine, context: viewContext)
                    importedRoutinesCount += 1
                }
            }
            
            if importedRoutinesCount > 0 {
                try viewContext.save()
                showRoutineImportAlert = true
                logger.info("Successfully imported \(importedRoutinesCount) routines")
            } else {
                logger.info("No new routines to import (all already exist)")
            }
        } catch {
            logger.error("Failed to import routines", error: error)
        }
    }
}

