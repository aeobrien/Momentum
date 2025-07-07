import SwiftUI

struct BackupRestoreView: View {
    @StateObject private var backupManager = iCloudBackupManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var showingRestoreAlert = false
    @State private var selectedBackup: iCloudBackupManager.BackupInfo?
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: iCloudBackupManager.BackupInfo?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedBackupForDetail: iCloudBackupManager.BackupInfo?
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("iCloud Backup Status")) {
                    HStack {
                        Text("iCloud Available")
                        Spacer()
                        Image(systemName: backupManager.iCloudAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(backupManager.iCloudAvailable ? .green : .red)
                    }
                    
                    if let lastBackup = backupManager.lastBackupDate {
                        HStack {
                            Text("Last Backup")
                            Spacer()
                            Text(lastBackup, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button(action: createBackup) {
                        HStack {
                            Label("Create Backup Now", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            if backupManager.isBackupInProgress {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(backupManager.isBackupInProgress || !backupManager.iCloudAvailable)
                }
                
                if !backupManager.availableBackups.isEmpty {
                    Section(header: Text("Available Backups")) {
                        ForEach(backupManager.availableBackups, id: \.url) { backup in
                            Button(action: {
                                selectedBackupForDetail = backup
                            }) {
                                VStack(alignment: .leading) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(backup.deviceName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(backup.createdDate, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(formatFileSize(backup.fileSize))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .imageScale(.small)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .contextMenu {
                                Button(action: {
                                    selectedBackup = backup
                                    showingRestoreAlert = true
                                }) {
                                    Label("Restore", systemImage: "arrow.clockwise")
                                }
                                Button(action: {
                                    backupToDelete = backup
                                    showingDeleteAlert = true
                                }) {
                                    Label("Delete Backup", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Information")) {
                    Text("Automatic backups are created daily when the app is launched.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Backups include all tasks, routines, completion times, and preferences.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("CloudKit sync is still active and provides real-time synchronization across devices.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Restore Backup?", isPresented: $showingRestoreAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) {
                    if let backup = selectedBackup {
                        restoreBackup(backup)
                    }
                }
            } message: {
                Text("This will replace all current data with the backup from \(selectedBackup?.deviceName ?? ""). This action cannot be undone.")
            }
            .alert("Delete Backup?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let backup = backupToDelete {
                        deleteBackup(backup)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this backup? This action cannot be undone.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $selectedBackupForDetail) { backup in
                BackupDetailView(backupInfo: backup)
            }
        }
        .task {
            await backupManager.loadAvailableBackups()
        }
    }
    
    private func createBackup() {
        Task {
            do {
                try await backupManager.createBackup(context: viewContext)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func restoreBackup(_ backup: iCloudBackupManager.BackupInfo) {
        Task {
            do {
                try await backupManager.restoreFromBackup(at: backup.url, context: viewContext)
                presentationMode.wrappedValue.dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func deleteBackup(_ backup: iCloudBackupManager.BackupInfo) {
        Task {
            do {
                try await backupManager.deleteBackup(at: backup.url)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}