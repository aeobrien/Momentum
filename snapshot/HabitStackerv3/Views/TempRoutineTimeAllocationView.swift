import SwiftUI

struct TempRoutineTimeAllocationView: View {
    let taskNames: [String]
    @State private var taskDurations: [Int] = [] // Duration in minutes for each task
    @State private var showRunner = false
    @StateObject private var runnerWrapper = TempRunnerWrapper()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    private let logger = AppLogger.create(subsystem: "com.app.TempRoutineTimeAllocationView", category: "UI")
    
    init(taskNames: [String]) {
        self.taskNames = taskNames
        // Initialize with default 10 minutes per task
        _taskDurations = State(initialValue: Array(repeating: 10, count: taskNames.count))
        print("[TempRoutineTimeAllocationView] Initialized with \(taskNames.count) tasks: \(taskNames)")
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Instructions
                Text("Set duration for each task")
                    .font(.headline)
                    .padding(.top)
                
                // Debug: Show task count
                Text("Tasks: \(taskNames.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Scrollable list of tasks with time inputs
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Array(taskNames.enumerated()), id: \.offset) { index, taskName in
                            HStack {
                                // Task name
                                Text(taskName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Duration input
                                HStack {
                                    TextField("10", value: $taskDurations[index], format: .number)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 60)
                                        .keyboardType(.numberPad)
                                    
                                    Text("min")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // Total time display
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        Text("Total time:")
                            .font(.headline)
                        Spacer()
                        Text(formatTotalDuration())
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }
                
                // Start button
                Button(action: startTempRoutine) {
                    Text("Start Routine")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Set Task Times")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                print("[TempRoutineTimeAllocationView] onAppear - tasks: \(taskNames)")
                logger.info("View appeared with \(taskNames.count) tasks")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showRunner, onDismiss: {
                TempRoutineStorage.clear()
                runnerWrapper.runner = nil
            }) {
                Group {
                    if let runner = runnerWrapper.runner {
                        TempRoutineRunnerView(runner: runner)
                            .onAppear {
                                logger.info("TempRoutineRunnerView appeared with runner")
                            }
                    } else {
                        VStack {
                            Text("Error: Runner not initialized")
                                .foregroundColor(.red)
                                .onAppear {
                                    logger.error("fullScreenCover presented but runnerWrapper.runner is nil")
                                }
                            Button("Dismiss") {
                                showRunner = false
                            }
                            .padding()
                        }
                    }
                }
            }
        }
    }
    
    private func formatTotalDuration() -> String {
        let totalMinutes = taskDurations.reduce(0, +)
        if totalMinutes < 60 {
            return "\(totalMinutes) minutes"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
    
    private func startTempRoutine() {
        logger.info("Starting temporary routine with \(taskNames.count) tasks")
        
        // Create temporary tasks
        var tempTasks: [TempTask] = []
        
        for (index, taskName) in taskNames.enumerated() {
            let tempTask = TempTask(
                name: taskName,
                duration: taskDurations[index]
            )
            tempTasks.append(tempTask)
        }
        
        // Create runner with temporary tasks
        let runner = TempRoutineRunner(tasks: tempTasks)
        runnerWrapper.runner = runner
        logger.info("TempRoutineRunner created and assigned to runnerWrapper")
        
        // Small delay to ensure runner is properly set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.runnerWrapper.runner != nil {
                showRunner = true
                logger.info("Presenting TempRoutineRunnerView - runner is set")
            } else {
                logger.error("runnerWrapper.runner is nil when trying to present")
            }
        }
        
        logger.info("Temporary routine started successfully")
    }
}

struct TempRoutineTimeAllocationView_Previews: PreviewProvider {
    static var previews: some View {
        TempRoutineTimeAllocationView(taskNames: ["Task 1", "Task 2", "Task 3"])
    }
}