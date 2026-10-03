import Foundation


struct CustomTask: Identifiable, Codable, Equatable {
    var id: String { UUID }
    var UUID: String
    var taskName: String
    var essentiality: Int?
    var minDuration: Int
    var maxDuration: Int
    var lastCompleted: String?
    var repetitionInterval: Int?
    let order: Int?
    
    var startTime: Date? = nil
    var expectedEndTime: Date? = nil

    // Maintain the original manual initializer
    init(UUID: String,
         taskName: String,
         essentiality: Int?,
         minDuration: Int,
         maxDuration: Int,
         lastCompleted: String?,
         repetitionInterval: Int?,
         order: Int?) {
        self.UUID = UUID
        self.taskName = taskName
        self.essentiality = essentiality
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.lastCompleted = lastCompleted
        self.repetitionInterval = repetitionInterval
        self.order = order
    }

    enum CodingKeys: String, CodingKey {
           case UUID = "id"
           case taskName = "task"
           case essentiality = "priority"
           case minDuration = "duration"  // Only map duration once
           case lastCompleted = "lastCompletion"
           case repetitionInterval
           case order
       }
    
    init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Decode the basic properties
            UUID = try container.decode(String.self, forKey: .UUID)
            taskName = try container.decode(String.self, forKey: .taskName)
            essentiality = try container.decodeIfPresent(Int.self, forKey: .essentiality)
            lastCompleted = try container.decodeIfPresent(String.self, forKey: .lastCompleted)
            repetitionInterval = try container.decodeIfPresent(Int.self, forKey: .repetitionInterval)
            order = try container.decodeIfPresent(Int.self, forKey: .order)
            
            // Handle duration - set both min and max to the same value
            let duration = try container.decode(Int.self, forKey: .minDuration)
            minDuration = duration
            maxDuration = duration
            
            // Initialize optional properties
            startTime = nil
            expectedEndTime = nil
        }
}


struct TaskInstance: Identifiable, Equatable {
    let id = UUID()  // or you can use task.id if CustomTask has a unique identifier
    var task: CustomTask
    var startTime: Date? = nil
    var expectedEndTime: Date? = nil
    var isCompleted: Bool = false
    
    // Add Equatable conformance
        static func == (lhs: TaskInstance, rhs: TaskInstance) -> Bool {
            return lhs.task == rhs.task && lhs.isCompleted == rhs.isCompleted
        }
}

// Add this struct to handle the JSON wrapper
struct TaskListContainer: Codable {
    let version: String
    let tasks: [CustomTask]
}

struct CustomPlaylist: Codable {
    let playlistName: String
    let createdOn: String
    let taskUUIDs: [String]

    enum CodingKeys: String, CodingKey {
        case playlistName = "playlist_name"  // Mapping JSON key "playlist_name" to "playlistName"
        case createdOn = "created_on"  // Mapping JSON key "created_on" to "createdOn"
        case taskUUIDs = "tasks"  // Mapping JSON key "tasks" to "taskUUIDs"
    }
}

// Update TaskResponse to handle the JSON structure
struct TaskResponse: Codable {
    let version: String
    let tasks: [CustomTask]
}


class CustomTaskManager: ObservableObject {
    @Published var tasks: [CustomTask] = []
    @Published var playlist: CustomPlaylist?
    

    init(selectedRoutine: String) {
        // Load from the documents directory if available; otherwise, load from the bundle
        if !loadTasksFromDocumentsDirectory() {
            loadTasksFromBundle()
        }
        loadPlaylist(for: selectedRoutine)
    }

    private func loadTasksFromBundle() {
        guard let url = Bundle.main.url(forResource: "FullTaskListv2", withExtension: "json") else {
            print("Failed to find FullTaskListv2.json in the bundle.")
            return
        }
        print("Tasks JSON path: \(url)")
        do {
            let data = try Data(contentsOf: url)
            print("📦 JSON data size: \(data.count) bytes")
            let container = try JSONDecoder().decode(TaskListContainer.self, from: data)
            tasks = container.tasks
            print("📦 Successfully loaded \(tasks.count) tasks from bundle.")
            tasks.forEach { task in
                print("📦 Loaded task: \(task.taskName), UUID: \(task.UUID)")
            }
        } catch {
            print("Failed to load tasks from bundle: \(error)")
            print(String(data: try! Data(contentsOf: url), encoding: .utf8) ?? "Could not read data as string")
        }
    }


    // Also update loadTasksFromDocumentsDirectory():
    @discardableResult
    func loadTasksFromDocumentsDirectory() -> Bool {
        let url = getDocumentsDirectory().appendingPathComponent("tasks.json")
        do {
            let data = try Data(contentsOf: url)
            let container = try JSONDecoder().decode(TaskListContainer.self, from: data)
            tasks = container.tasks
            print("Tasks loaded successfully from documents directory.")
            return true
        } catch {
            print("Failed to load tasks from documents directory: \(error)")
            return false
        }
    }

    func saveTasks(tasks: [CustomTask]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(tasks)
            let url = getDocumentsDirectory().appendingPathComponent("tasks.json")
            try data.write(to: url)
            print("Tasks saved successfully to documents directory.")
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }

    func loadPlaylist(for routine: String) {
        let routineNameForFile = routine.replacingOccurrences(of: " ", with: "")
        let fileName = "\(routineNameForFile.capitalized)Routine.json"
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentFilePath = documentsURL.appendingPathComponent(fileName)
        
        print("Attempting to load playlist: \(fileName)")
        print("Checking path: \(documentFilePath.path)")
        
        if fileManager.fileExists(atPath: documentFilePath.path) {
            print("File found in documents directory")
            loadPlaylistFromURL(documentFilePath)
        } else if let bundleURL = Bundle.main.url(forResource: routineNameForFile.capitalized + "Routine", withExtension: "json") {
            print("File found in bundle")
            loadPlaylistFromURL(bundleURL)
        } else {
            print("Failed to find \(fileName) in documents directory or bundle.")
            print("Documents directory contents:")
            do {
                let contents = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                for file in contents {
                    print(file.lastPathComponent)
                }
            } catch {
                print("Error listing directory contents: \(error)")
            }
        }
    }

    private func loadPlaylistFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            playlist = try JSONDecoder().decode(CustomPlaylist.self, from: data)
            print("Successfully loaded playlist from \(url.lastPathComponent)")
            print("Playlist contents: \(playlist?.taskUUIDs ?? [])")
        } catch {
            print("Failed to load playlist from \(url.lastPathComponent): \(error)")
        }
    }

    func getFilteredTasks(currentTime: Date) -> [CustomTask] {
        guard let playlist = playlist else {
            print("🔍 No playlist loaded")
            return []
        }
        
        print("🔍 getFilteredTasks - Starting")
        print("🔍 Total tasks available: \(tasks.count)")
        print("🔍 First 5 task UUIDs: ")
        tasks.prefix(5).forEach { task in
            print("   \(task.UUID)")
        }
        print("🔍 First 5 playlist UUIDs:")
        playlist.taskUUIDs.prefix(5).forEach { uuid in
            print("   \(uuid)")
        }
        
        let filteredTasks = tasks.filter { task in
            let matches = playlist.taskUUIDs.contains { playlistUUID in
                print("🔍 Comparing task '\(task.taskName)' UUID: \(task.UUID)")
                print("   with playlist UUID: \(playlistUUID)")
                return task.UUID == playlistUUID
            }
            print("   Match found: \(matches)")
            return matches
        }
        
        print("🔍 Filtered tasks count: \(filteredTasks.count)")
        print("🔍 Filtered tasks:")
        filteredTasks.forEach { task in
            print("   - \(task.taskName)")
        }
        
        return filteredTasks
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
extension String {
    func toDate() -> Date? {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter.date(from: self)
    }
}
