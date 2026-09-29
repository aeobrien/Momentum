import SwiftUI

struct CustomTaskPriorityView: View {
    let availableTime: TimeInterval
    @State private var tasks: [CustomTask] = []
    @State private var orderedTaskUUIDs: [String] = []
    @State private var scheduledTasks: [(task: CustomTask, duration: Int)] = []
    @State private var showRoutineRunner = false
    @State private var currentTime: Date = Date()
    
    let selectedRoutine: String
    private let taskManager: CustomTaskManager
    @State private var taskScheduler = TaskScheduler(currentTime: Date())
    
    init(availableTime: TimeInterval, selectedRoutine: String) {
        self.availableTime = availableTime
        self.selectedRoutine = selectedRoutine
        self.taskManager = CustomTaskManager(selectedRoutine: selectedRoutine)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack {
                    VStack {
                        Text("Available")
                            .font(.headline)
                        Text(formatTimeInterval(availableTime))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    VStack {
                        Text("Scheduled")
                            .font(.headline)
                        Text(formatTimeInterval(scheduledTasks.reduce(0) { $0 + TimeInterval($1.duration) }))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                List {
                    ForEach(scheduledTasks.indices, id: \.self) { index in
                        HStack {
                            Spacer() // Add leading spacer to center the tile
                            HStack {
                                Text(scheduledTasks[index].task.taskName)
                                    .font(.headline)
                                    .padding(.leading, 10)
                                Spacer()
                                Text("\(scheduledTasks[index].duration / 60) min")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 10)
                            }
                            .padding(.vertical, 8)
                            .frame(width: geometry.size.width * 0.83) // Adjust width to avoid cutoff
                            .background(Color(.secondarySystemBackground).opacity(1)) // Slight opacity for transparency during drag
                            .cornerRadius(10)
                            .shadow(radius: 1)
                            Spacer() // Add trailing spacer to center the tile
                        }
                        .listRowInsets(EdgeInsets()) // Remove extra insets
                        .listRowSeparator(.hidden) // Hides the default separator
                        .id(scheduledTasks[index].task.taskName) // Ensure stable identifier for dragging
                    }
                    .onMove { indices, newOffset in
                        scheduledTasks.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(PlainListStyle())
                .frame(height: geometry.size.height * 0.7)
                .padding(.horizontal, 10)
                
                Spacer()
                
                Button(action: {
                    showRoutineRunner = true
                }) {
                    Text("Start Routine")
                        .font(.title2)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .shadow(radius: 5)
                }
                .padding([.horizontal, .bottom], 20)
                .fullScreenCover(isPresented: $showRoutineRunner) {
                    RoutineRunnerView(
                        tasks: Binding<[CustomTask]>(
                            get: { scheduledTasks.map { $0.task } },
                            set: { newTasks in
                                for (index, task) in newTasks.enumerated() {
                                    scheduledTasks[index].task = task
                                }
                            }
                        ),
                        showRoutineRunner: $showRoutineRunner,
                        availableTime: availableTime // Add this line
                    )
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .onAppear {
                fetchTasks()
                scheduleTasks()
                reorderScheduledTasks()
                printScheduledTasks()
            }
        }
    }
    

    private func fetchTasks() {
            // Get filtered tasks from task manager
            tasks = taskManager.getFilteredTasks(currentTime: currentTime)
            
            // Sort tasks based on playlist order
            tasks.sort { task1, task2 in
                if let uuids = taskManager.playlist?.taskUUIDs,
                   let index1 = uuids.firstIndex(of: task1.UUID),
                   let index2 = uuids.firstIndex(of: task2.UUID) {
                    return index1 < index2
                }
                return false
            }
            print("Fetched \(tasks.count) tasks")
        }
    
    private func scheduleTasks() {
        let filteredTasks = tasks.filter { taskManager.playlist?.taskUUIDs.contains($0.UUID) ?? false }
        scheduledTasks = taskScheduler.scheduleTasks(filteredTasks: filteredTasks, availableTime: availableTime)
    }
    
    private func reorderScheduledTasks() {
        scheduledTasks.sort { (first, second) -> Bool in
            guard let firstIndex = orderedTaskUUIDs.firstIndex(of: first.task.UUID),
                  let secondIndex = orderedTaskUUIDs.firstIndex(of: second.task.UUID) else {
                return false
            }
            return firstIndex < secondIndex
        }
    }
    
    private func printScheduledTasks() {
        print("Scheduled tasks:")
        for task in scheduledTasks {
            print("Task: \(task.task.taskName), Duration: \(task.duration) seconds")
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
    
    private func getDocumentsDirectoryFileURL(fileName: String) -> URL? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    private func copyJSONFileToDocumentsDirectoryIfNeeded(fileName: String) {
        let fileManager = FileManager.default
        guard let documentsURL = getDocumentsDirectoryFileURL(fileName: fileName) else {
            print("Failed to get documents directory URL.")
            return
        }
        
        if !fileManager.fileExists(atPath: documentsURL.path) {
            if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
                do {
                    try fileManager.copyItem(at: bundleURL, to: documentsURL)
                    print("Copied \(fileName) to documents directory.")
                } catch {
                    print("Failed to copy \(fileName) to documents directory: \(error)")
                }
            } else {
                print("\(fileName) not found in bundle.")
            }
        } else {
            print("\(fileName) already exists in documents directory.")
        }
    }
    
}
