import SwiftUI
import CloudKit

/// Test view to verify CloudKit sync functionality
struct CloudKitTestView: View {
    @ObservedObject var syncManager = CloudKitSyncManager.shared
    @State private var testMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Sync Status
            HStack {
                Image(systemName: syncManager.syncStatus.symbolName)
                    .foregroundColor(syncManager.syncStatus.color)
                    .font(.title2)
                Text(syncManager.syncStatus.description)
                    .font(.headline)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // iCloud Availability
            HStack {
                Text("iCloud Available:")
                Text(CoreDataStack.shared.isCloudKitAvailable ? "Yes" : "No")
                    .foregroundColor(CoreDataStack.shared.isCloudKitAvailable ? .green : .red)
                    .fontWeight(.bold)
            }
            
            // Last Sync Date
            if let lastSync = syncManager.lastSyncDate {
                HStack {
                    Text("Last Sync:")
                    Text(lastSync, style: .relative)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sync Error
            if let error = syncManager.syncError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Test Actions
            VStack(spacing: 15) {
                Button("Check CloudKit Status") {
                    syncManager.checkCloudKitStatus()
                    testMessage = "Checking CloudKit status..."
                }
                .buttonStyle(.borderedProminent)
                
                Button("Force Sync Preferences") {
                    CloudKitPreferences.shared.forceSync()
                    testMessage = "Forcing preference sync..."
                }
                .buttonStyle(.bordered)
                
                Button("Test Create Task") {
                    testCreateTask()
                }
                .buttonStyle(.bordered)
                
                Button("Test Update Routine") {
                    testUpdateRoutine()
                }
                .buttonStyle(.bordered)
            }
            
            if !testMessage.isEmpty {
                Text(testMessage)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("CloudKit Test")
    }
    
    private func testCreateTask() {
        let context = CoreDataStack.shared.viewContext
        let newTask = CDTask(context: context)
        newTask.uuid = UUID()
        newTask.taskName = "Test CloudKit Task \(Date().timeIntervalSince1970)"
        newTask.essentiality = 2
        newTask.isSessionTask = false
        newTask.minDuration = 300
        newTask.maxDuration = 600
        
        do {
            try context.save()
            testMessage = "Created test task - check if it syncs to iCloud"
        } catch {
            testMessage = "Error creating task: \(error.localizedDescription)"
        }
    }
    
    private func testUpdateRoutine() {
        let context = CoreDataStack.shared.viewContext
        let fetchRequest = CDRoutine.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        do {
            if let routine = try context.fetch(fetchRequest).first {
                routine.name = "Updated at \(Date().formatted())"
                try context.save()
                testMessage = "Updated routine - check if change syncs"
            } else {
                // Create a new routine if none exists
                let newRoutine = CDRoutine(context: context)
                newRoutine.uuid = UUID()
                newRoutine.name = "Test CloudKit Routine"
                newRoutine.createdOn = Date()
                newRoutine.lastUsed = Date()
                try context.save()
                testMessage = "Created test routine - check if it syncs"
            }
        } catch {
            testMessage = "Error updating routine: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
struct CloudKitTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CloudKitTestView()
        }
    }
}
#endif