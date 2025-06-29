import SwiftUI
import CloudKit
import CoreData

struct CloudKitDebugView: View {
    @State private var coreDataRecords: [String] = []
    @State private var cloudKitRecords: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var containerStatus: String = "Checking..."
    
    var body: some View {
        NavigationView {
            List {
                Section("CloudKit Status") {
                    HStack {
                        Text("Container:")
                        Text("iCloud.AOTondra.Momentum")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status:")
                        Text(containerStatus)
                            .foregroundColor(containerStatus.contains("Active") ? .green : .orange)
                    }
                }
                
                Section("Core Data Records") {
                    Text("Total Records: \(coreDataRecords.count)")
                        .font(.headline)
                    
                    ForEach(coreDataRecords, id: \.self) { record in
                        Text(record)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
                
                Section("CloudKit Records (Direct Query)") {
                    if isLoading {
                        ProgressView("Loading CloudKit records...")
                    } else if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                    } else {
                        Text("CloudKit Records: \(cloudKitRecords.count)")
                            .font(.headline)
                        
                        ForEach(cloudKitRecords, id: \.self) { record in
                            Text(record)
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Refresh Core Data") {
                        loadCoreDataRecords()
                    }
                    
                    Button("Query CloudKit Directly") {
                        queryCloudKitDirectly()
                    }
                    
                    Button("Check CloudKit Schema") {
                        checkCloudKitSchema()
                    }
                    
                    Button("Force Sync") {
                        forceSync()
                    }
                }
            }
            .navigationTitle("CloudKit Debug")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh All") {
                        refreshAll()
                    }
                }
            }
        }
        .onAppear {
            checkContainerStatus()
            loadCoreDataRecords()
        }
    }
    
    private func checkContainerStatus() {
        let container = CKContainer(identifier: "iCloud.AOTondra.Momentum")
        
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    containerStatus = "Error: \(error.localizedDescription)"
                } else {
                    switch status {
                    case .available:
                        containerStatus = "Active ✅"
                    case .noAccount:
                        containerStatus = "No iCloud Account"
                    case .restricted:
                        containerStatus = "Restricted"
                    case .temporarilyUnavailable:
                        containerStatus = "Temporarily Unavailable"
                    case .couldNotDetermine:
                        containerStatus = "Could Not Determine"
                    @unknown default:
                        containerStatus = "Unknown"
                    }
                }
            }
        }
    }
    
    private func loadCoreDataRecords() {
        let context = CoreDataStack.shared.viewContext
        var records: [String] = []
        
        // Fetch Tasks
        let taskRequest = CDTask.fetchRequest()
        if let tasks = try? context.fetch(taskRequest) {
            for task in tasks {
                records.append("Task: \(task.taskName ?? "Unknown") - ID: \(task.uuid?.uuidString ?? "No UUID")")
            }
        }
        
        // Fetch Routines
        let routineRequest = CDRoutine.fetchRequest()
        if let routines = try? context.fetch(routineRequest) {
            for routine in routines {
                records.append("Routine: \(routine.name ?? "Unknown") - ID: \(routine.uuid?.uuidString ?? "No UUID")")
            }
        }
        
        // Fetch Completion Times
        let completionRequest = CDTaskCompletionTime.fetchRequest()
        if let completions = try? context.fetch(completionRequest) {
            records.append("Completion Times: \(completions.count) records")
        }
        
        coreDataRecords = records
    }
    
    private func queryCloudKitDirectly() {
        isLoading = true
        errorMessage = nil
        cloudKitRecords = []
        
        let container = CKContainer(identifier: "iCloud.AOTondra.Momentum")
        let privateDatabase = container.privateCloudDatabase
        
        // Query for CD_CDTask records
        let taskQuery = CKQuery(recordType: "CD_CDTask", predicate: NSPredicate(value: true))
        // Remove sort descriptor to avoid queryable field requirement
        // taskQuery.sortDescriptors = [NSSortDescriptor(key: "CD_taskName", ascending: true)]
        
        privateDatabase.fetch(withQuery: taskQuery, inZoneWith: nil) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let matchResults):
                    var records: [String] = []
                    
                    for (recordID, recordResult) in matchResults.matchResults {
                        switch recordResult {
                        case .success(let record):
                            let taskName = record["CD_taskName"] as? String ?? "Unknown"
                            let uuid = record["CD_uuid"] as? String ?? "No UUID"
                            records.append("CloudKit Task: \(taskName)\nRecord ID: \(recordID.recordName)\nUUID: \(uuid)")
                        case .failure(let error):
                            records.append("Error fetching record \(recordID): \(error)")
                        }
                    }
                    
                    self.cloudKitRecords = records
                    self.isLoading = false
                    
                    // Also query for routines
                    self.queryRoutinesFromCloudKit()
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func queryRoutinesFromCloudKit() {
        let container = CKContainer(identifier: "iCloud.AOTondra.Momentum")
        let privateDatabase = container.privateCloudDatabase
        
        let routineQuery = CKQuery(recordType: "CD_CDRoutine", predicate: NSPredicate(value: true))
        
        privateDatabase.fetch(withQuery: routineQuery, inZoneWith: nil) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let matchResults):
                    for (recordID, recordResult) in matchResults.matchResults {
                        switch recordResult {
                        case .success(let record):
                            let routineName = record["CD_name"] as? String ?? "Unknown"
                            let uuid = record["CD_uuid"] as? String ?? "No UUID"
                            self.cloudKitRecords.append("CloudKit Routine: \(routineName)\nRecord ID: \(recordID.recordName)\nUUID: \(uuid)")
                        case .failure(let error):
                            self.cloudKitRecords.append("Error fetching routine: \(error)")
                        }
                    }
                case .failure(let error):
                    self.cloudKitRecords.append("Error querying routines: \(error)")
                }
            }
        }
    }
    
    private func checkCloudKitSchema() {
        errorMessage = nil
        cloudKitRecords = []
        
        // List expected record types
        let expectedTypes = [
            "CD_CDTask",
            "CD_CDRoutine", 
            "CD_CDRoutineTask",
            "CD_CDTaskCompletionTime",
            "UserPreferences"
        ]
        
        cloudKitRecords = expectedTypes.map { "Expected Record Type: \($0)" }
        
        // Also check sync status
        if let persistentStore = CoreDataStack.shared.persistentContainer.persistentStoreCoordinator.persistentStores.first {
            if let options = persistentStore.options {
                cloudKitRecords.append("\nStore Options:")
                for (key, value) in options {
                    cloudKitRecords.append("\(key): \(value)")
                }
            }
        }
    }
    
    private func forceSync() {
        // Trigger a Core Data save to force sync
        let context = CoreDataStack.shared.viewContext
        
        // Option 1: Touch multiple records to trigger sync
        let taskRequest = CDTask.fetchRequest()
        taskRequest.fetchLimit = 5
        
        var changesMade = 0
        if let tasks = try? context.fetch(taskRequest) {
            for task in tasks {
                // Make a minor change - just update the object
                task.willChangeValue(forKey: "taskName")
                task.didChangeValue(forKey: "taskName")
                changesMade += 1
            }
        }
        
        // Option 2: Create a test task to trigger sync
        if changesMade == 0 {
            let testTask = CDTask(context: context)
            testTask.uuid = UUID()
            testTask.taskName = "CloudKit Sync Test - \(Date().formatted())"
            testTask.essentiality = 1
            testTask.minDuration = 300
            testTask.maxDuration = 600
            changesMade = 1
        }
        
        do {
            try context.save()
            errorMessage = "Forced sync triggered for \(changesMade) records - wait a moment then check CloudKit"
            
            // Also trigger a fetch to pull any remote changes
            context.refreshAllObjects()
        } catch {
            errorMessage = "Error forcing sync: \(error)"
        }
    }
    
    private func refreshAll() {
        checkContainerStatus()
        loadCoreDataRecords()
        queryCloudKitDirectly()
    }
}

#if DEBUG
struct CloudKitDebugView_Previews: PreviewProvider {
    static var previews: some View {
        CloudKitDebugView()
    }
}
#endif