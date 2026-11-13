import SwiftUI

struct BackupDetailView: View {
    let backupInfo: iCloudBackupManager.BackupInfo
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var backupManager = iCloudBackupManager.shared
    
    @State private var backupData: BackupData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingRestoreAlert = false
    @State private var selectedSection = 0
    
    private let logger = AppLogger.create(subsystem: "com.AOTondra.Momentum", category: "BackupDetail")
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading backup...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error Loading Backup")
                            .font(.headline)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if let data = backupData {
                    VStack(spacing: 0) {
                        Picker("Section", selection: $selectedSection) {
                            Text("Summary").tag(0)
                            Text("Tasks (\(data.tasks.count))").tag(1)
                            Text("Routines (\(data.routines.count))").tag(2)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding()
                        
                        List {
                            switch selectedSection {
                            case 0:
                                summarySection(data)
                            case 1:
                                tasksSection(data)
                            case 2:
                                routinesSection(data)
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Backup Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Restore") {
                        showingRestoreAlert = true
                    }
                    .disabled(backupData == nil)
                }
            }
        }
        .task {
            await loadBackupData()
        }
        .alert("Restore Backup?", isPresented: $showingRestoreAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task {
                    await restoreBackup()
                }
            }
        } message: {
            Text("This will replace all current data with this backup. This action cannot be undone.")
        }
    }
    
    @ViewBuilder
    private func summarySection(_ data: BackupData) -> some View {
        Section(header: Text("Backup Information")) {
            HStack {
                Text("Created")
                Spacer()
                Text(data.createdDate, style: .date)
                Text(data.createdDate, style: .time)
            }
            
            HStack {
                Text("Device")
                Spacer()
                Text(data.deviceName)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Version")
                Spacer()
                Text(data.version)
                    .foregroundColor(.secondary)
            }
        }
        
        Section(header: Text("Contents")) {
            HStack {
                Label("Tasks", systemImage: "checklist")
                Spacer()
                Text("\(data.tasks.count)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Routines", systemImage: "star")
                Spacer()
                Text("\(data.routines.count)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Completion Records", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("\(data.taskCompletionTimes.count)")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func tasksSection(_ data: BackupData) -> some View {
        ForEach(data.tasks.sorted(by: { $0.taskName < $1.taskName }), id: \.uuid) { task in
            VStack(alignment: .leading, spacing: 4) {
                Text(task.taskName)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(task.minDuration)-\(task.maxDuration)m", systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if task.repetitionInterval > 0 {
                        Label("\(task.repetitionInterval / 86400)d", systemImage: "repeat")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Circle()
                        .fill(essentialityColor(task.essentiality))
                        .frame(width: 8, height: 8)
                }
                
                if let lastCompleted = task.lastCompleted {
                    Text("Last: \(lastCompleted, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func routinesSection(_ data: BackupData) -> some View {
        ForEach(data.routines.sorted(by: { $0.name < $1.name }), id: \.uuid) { routine in
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.headline)
                
                HStack {
                    if routine.totalCompletions > 0 {
                        Label("\(routine.totalCompletions) runs", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if routine.averageCompletionTime > 0 {
                        Label("\(Int(routine.averageCompletionTime / 60))m avg", systemImage: "timer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let lastUsed = routine.lastUsed {
                    Text("Last used: \(lastUsed, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                let taskCount = data.routineTasks.filter { $0.routineID == routine.uuid }.count
                Text("\(taskCount) tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func essentialityColor(_ value: Int16) -> Color {
        switch value {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .gray
        }
    }
    
    private func loadBackupData() async {
        isLoading = true
        errorMessage = nil
        
        let document = MomentumBackupDocument(fileURL: backupInfo.url)
        
        do {
            let opened = await withCheckedContinuation { continuation in
                document.open { success in
                    continuation.resume(returning: success)
                }
            }
            
            guard opened else {
                errorMessage = "Failed to open backup file"
                isLoading = false
                return
            }
            
            backupData = document.backupData
            document.close(completionHandler: nil)
            
            if backupData == nil {
                errorMessage = "Backup file is empty or corrupted"
            }
        } catch {
            logger.error("Failed to load backup: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func restoreBackup() async {
        do {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            try await backupManager.restoreFromBackup(at: backupInfo.url, context: context)
            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}