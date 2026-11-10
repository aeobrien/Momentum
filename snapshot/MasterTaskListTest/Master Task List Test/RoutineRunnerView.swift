// RoutineRunnerView.swift
import SwiftUI
import AVFoundation
import CoreHaptics
import AudioToolbox
import BackgroundTasks
import UserNotifications

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct RobustButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .contentShape(Rectangle())
    }
}

struct RoutineRunnerView: View {
    @Environment(\.scenePhase) var scenePhase
    @State private var detailsVisible: Bool = false
    @Binding var tasks: [CustomTask]
    @Binding var showRoutineRunner: Bool
    @State private var taskInstances: [TaskInstance] = []
    @State private var currentIndex: Int = 0
    @ObservedObject var sharedTaskManager = SharedTaskManager()
    @State private var positiveSound: AVAudioPlayer?
    @State private var negativeSound: AVAudioPlayer?
    @State private var paymentSuccessPlayer: AVAudioPlayer?

    @State private var timeRemaining: TimeInterval = 0
    @State private var overTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var lastOverUnderMinuteThreshold: Int = 0
    @State private var estimatedFinishingTime: Date?
    @State private var progress: Double = 0.0
    @State private var isMoving: Bool = false
    @State private var originalFinishingTime: Date? = nil

    // New state to control the task list modal
    @State private var showTaskListModal: Bool = false

    // Background task related states
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @State private var appDidEnterBackgroundDate: Date?
    
    @State private var viewReloaded = false
    
    @State private var lastCompletedTask: TaskInstance?
    @State private var lastCompletedTaskIndex: Int?
    @State private var lastTimeDifference: TimeInterval = 0



    // **New Property to Receive `availableTime`**
    var availableTime: TimeInterval

    var body: some View {
            GeometryReader { geometry in
                VStack {
                    Spacer()

                    if currentIndex < taskInstances.count {
                        let taskInstance = taskInstances[currentIndex]

                        VStack(spacing: 20) {
                            // Timer at the top when details are visible, closer to the task name when not
                            Text(timeRemaining > 0 ? formattedTaskDuration(timeRemaining) : formattedTaskDuration(overTime))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(timeRemaining > 0 ? .primary : .red)
                                .padding(.top, detailsVisible ? 20 : 0)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .transition(.move(edge: .top).combined(with: .opacity))

                            // Task name moves up when details are visible
                            Text(taskInstance.task.taskName)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(15)
                                .shadow(radius: 5)
                                .multilineTextAlignment(.center)
                                .foregroundColor(timeRemaining > 0 ? .primary : .red)
                                .onTapGesture {
                                    withAnimation(.easeInOut) {
                                        detailsVisible.toggle()
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .transition(detailsVisible ? .move(edge: .top).combined(with: .opacity) : .opacity)

                            // Icons placed directly underneath the task name
                            if detailsVisible {
                                HStack(spacing: 50) {
                                    Button(action: {
                                        undoLastTaskCompletion()
                                    }) {
                                        Image(systemName: "arrow.uturn.left.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(RobustButtonStyle())

                                    Button(action: {
                                        skipTask()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.yellow)
                                    }
                                    .buttonStyle(RobustButtonStyle())

                                    Button(action: {
                                        comeBackToThis()
                                    }) {
                                        Image(systemName: "arrow.uturn.right.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.orange)
                                    }
                                    .buttonStyle(RobustButtonStyle())

                                    Button(action: {
                                        showTaskListModal = true
                                    }) {
                                        Image(systemName: "list.bullet")
                                            .font(.title)
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(RobustButtonStyle())
                                }
                                .padding(.top, 10)

                                Spacer()

                                // Use Spacer to push content apart
                                Spacer()

                                // Text display for finishing time and over/under schedule
                                VStack(alignment: .center, spacing: 10) {
                                    if let estimatedTime = estimatedFinishingTime {
                                        Text("Finishing at: \(formattedTime(estimatedTime))")
                                            .font(.headline)
                                            .multilineTextAlignment(.center)
                                            .transition(.opacity)
                                    }

                                    if sharedTaskManager.overUnderTime == 0 {
                                        Text("On schedule!")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                            .multilineTextAlignment(.center)
                                            .transition(.opacity)
                                    } else if sharedTaskManager.overUnderTime > 0 {
                                        Text("\(formattedTaskDuration(sharedTaskManager.overUnderTime)) ahead of schedule")
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                            .multilineTextAlignment(.center)
                                            .transition(.opacity)
                                    } else {
                                        Text("\(formattedTaskDuration(-sharedTaskManager.overUnderTime)) behind schedule")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                            .multilineTextAlignment(.center)
                                            .transition(.opacity)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .bottom).combined(with: .opacity))

                                // Spacer to push "Coming up" section down
                                Spacer()

                                if currentIndex + 1 < taskInstances.count {
                                    let nextTask = taskInstances[currentIndex + 1]

                                    VStack(spacing: 10) {
                                        Text("Coming up:")
                                            .font(.headline)
                                            .transition(.opacity)

                                        Text(nextTask.task.taskName)
                                            .font(.system(size: 24, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .transition(.opacity)
                                    }
                                    .padding(.top, 20)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }

                            // Button slides down when details are visible
                            Button(action: {
                                print("Done button tapped")
                                completeCurrentTask()
                            }) {
                                Text("Done!")
                                    .font(.title2)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(15)
                                    .shadow(radius: 5)
                            }
                            .buttonStyle(RobustButtonStyle())
                            .padding([.horizontal, .bottom], detailsVisible ? 20 : 60)
                            .frame(maxWidth: .infinity)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: detailsVisible ? .top : .center
                        )
                    } else {
                        Spacer()

                        Text("All tasks completed!")
                            .font(.largeTitle)
                            .padding()

                        Button(action: {
                            showRoutineRunner = false
                        }) {
                            Text("Finish")
                                .font(.title2)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                                .shadow(radius: 5)
                        }
                        .buttonStyle(RobustButtonStyle())
                        .padding()
                    }

                    Spacer(minLength: 0)
                }
                .background(Color(.systemBackground))
                        .onAppear {
                            print("RoutineRunnerView appeared")
                            print("Current index: \(currentIndex)")
                            print("Tasks count: \(taskInstances.count)")
                            print("SharedTaskManager tasks count: \(sharedTaskManager.tasks.count)")
                            if sharedTaskManager.tasks.isEmpty {
                                print("Reinitializing sharedTaskManager")
                                reinitializeSharedTaskManager()
                            }
                            if !viewReloaded {
                                setupRoutine()
                                startNextTask()
                                registerBackgroundTask()
                                viewReloaded = true
                            }
                        }
                        .onDisappear {
                            print("RoutineRunnerView disappeared")
                            print("Current index: \(currentIndex)")
                            print("Tasks count: \(taskInstances.count)")
                            print("SharedTaskManager tasks count: \(sharedTaskManager.tasks.count)")
                            timer?.invalidate()
                            endBackgroundTask()
                        }
                        .onChange(of: UIDevice.current.orientation) { newOrientation in
                            print("Orientation changed to: \(newOrientation)")
                            print("Current index: \(currentIndex)")
                            print("Tasks count: \(taskInstances.count)")
                            print("SharedTaskManager tasks count: \(sharedTaskManager.tasks.count)")
                            if sharedTaskManager.tasks.isEmpty {
                                print("Reinitializing sharedTaskManager after orientation change")
                                reinitializeSharedTaskManager()
                            }
                        }
                        .id(UIDevice.current.orientation)
                        .sheet(isPresented: $showTaskListModal) {
                            VStack {
                                Text("Task List")
                                    .font(.headline)
                                    .padding()

                                ScrollViewReader { scrollProxy in
                                    List(taskInstances) { taskInstance in
                                        HStack {
                                            // Display the task name with strikethrough if it's completed
                                            Text(taskInstance.task.taskName)
                                                .strikethrough(taskInstance.isCompleted, color: .gray)
                                                .foregroundColor(taskInstance.isCompleted ? .gray : .primary)

                                            Spacer()

                                            // Show tick for completed tasks
                                            if taskInstance.isCompleted {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            } else {
                                                Image(systemName: "circle")
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .id(taskInstance.id) // Make sure each item has an ID for scrolling
                                    }
                                    .onAppear {
                                        // Find the index of the last completed task
                                        if let lastCompletedIndex = taskInstances.lastIndex(where: { $0.isCompleted }) {
                                            // Scroll to the last completed task
                                            scrollProxy.scrollTo(taskInstances[lastCompletedIndex].id, anchor: .top)
                                        }
                                    }
                                }
                            }
                        }

            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    print("App moved to the background")
                    saveTimerState()
                    scheduleBackgroundNotifications()
                } else if newPhase == .active {
                    print("App moved to the foreground")
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    restoreTimerState()
                }
            }
        }
    }
    private func reinitializeSharedTaskManager() {
        sharedTaskManager.tasks = taskInstances
        sharedTaskManager.calculateTotalTime()
        sharedTaskManager.calculateExpectedEndTime(from: Date())
    }
    
    func formattedTime(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }

    
    func undoLastTaskCompletion() {
        guard let lastTask = lastCompletedTask, let lastIndex = lastCompletedTaskIndex else {
            print("No task to undo.")
            return
        }

        // Mark the last task as incomplete
        taskInstances[lastIndex].isCompleted = false
        currentIndex = lastIndex

        // Revert the over/under time using the stored lastTimeDifference
        sharedTaskManager.overUnderTime -= lastTimeDifference

        // Recalculate the total time and update the expected end time
        sharedTaskManager.calculateTotalTime()
        sharedTaskManager.calculateExpectedEndTime(from: Date())  // Recalculate from current time

        // Clear the last completed task and time difference
        lastCompletedTask = nil
        lastCompletedTaskIndex = nil
        lastTimeDifference = 0

        // Make the undone task active again
        startNextTask()

        print("Undo completed for task: \(lastTask.task.taskName)")
    }




    
    func logToFile(_ message: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent("log.txt")
        if let data = "\(Date()): \(message)\n".data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func scheduleBackgroundNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests() // Remove any existing notifications

        for minute in 1...3 { // Adjust range as needed for how many minutes you want to notify
            let content = UNMutableNotificationContent()
            content.title = "Don't forget!"
            content.body = "You're supposed to be completing a task! Tap here to get back to it."
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minute * 60), repeats: false)
            
            let request = UNNotificationRequest(identifier: "taskReminder-\(minute)", content: content, trigger: trigger)
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error)")
                } else {
                    print("Scheduled notification for \(minute) minute(s)")
                }
            }
        }
    }
    
    func saveTimerState() {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: "backgroundedDate")
        defaults.set(timeRemaining, forKey: "timeRemaining")
        defaults.set(overTime, forKey: "overTime")
        defaults.set(currentIndex, forKey: "currentIndex")
        defaults.synchronize()
        
        print("Saved timer state: timeRemaining=\(timeRemaining), overTime=\(overTime), currentIndex=\(currentIndex)")
    }
    
    // Register background task
        func registerBackgroundTask() {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "RoutineRunner") {
                endBackgroundTask()
            }
            appDidEnterBackgroundDate = Date()
        }

        // End background task
        func endBackgroundTask() {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }

        // Handle app entering background
        func appDidEnterBackground() {
            if let enterBackgroundDate = appDidEnterBackgroundDate {
                let timeSpentInBackground = Date().timeIntervalSince(enterBackgroundDate)
                adjustTimers(for: timeSpentInBackground)
            }
        }

        // Adjust timers after returning from background
        func adjustTimers(for timeInterval: TimeInterval) {
            timeRemaining -= timeInterval
            if timeRemaining < 0 {
                overTime += abs(timeRemaining)
                timeRemaining = 0
                triggerHapticFeedback(isPositive: false)
                playNegativeSound()
            }
            updateEstimatedFinishingTimeIfNeeded()
            updateProgress()
        }
    
    func enterBackground() {
        print("App entering background.")
        appDidEnterBackgroundDate = Date()
        saveTimerState()
        scheduleBackgroundNotifications() // Schedule notifications when entering background
        startBackgroundTask()
    }

    func enterForeground() {
        print("App entering foreground.")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests() // Remove notifications when the app becomes active
        restoreTimerState() // Restore the state of the timer
        endBackgroundTask()
    }

        func startBackgroundTask() {
            backgroundTask = UIApplication.shared.beginBackgroundTask {
                self.endBackgroundTask()
            }
        }

    func sceneWillResignActive(_ scene: UIScene) {
        saveTimerState()
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests() // Remove notifications when app becomes active
        restoreTimerState() // Restore the state of the timer
    }
    
    
    func restoreTimerState() {
        let defaults = UserDefaults.standard
        if let backgroundedDate = defaults.object(forKey: "backgroundedDate") as? Date {
            let elapsedTime = Date().timeIntervalSince(backgroundedDate)
            
            print("Restoring timer state after \(elapsedTime) seconds.")
            
            if timeRemaining > 0 {
                timeRemaining -= elapsedTime
                if timeRemaining < 0 {
                    overTime = -timeRemaining
                    timeRemaining = 0
                    print("Task is now overdue. OverTime=\(overTime)")
                    playNegativeSound()
                    triggerHapticFeedback(isPositive: false)
                }
            } else {
                overTime += elapsedTime
                print("Continued OverTime. OverTime=\(overTime)")
            }

            sharedTaskManager.overUnderTime -= elapsedTime
            updateEstimatedFinishingTimeIfNeeded()
            updateProgress()
            startTimer()
            
            // Clear saved state
            defaults.removeObject(forKey: "backgroundedDate")
            defaults.removeObject(forKey: "timeRemaining")
            defaults.removeObject(forKey: "overTime")
            defaults.removeObject(forKey: "currentIndex")
            
            print("Timer state restored: timeRemaining=\(timeRemaining), overTime=\(overTime), currentIndex=\(currentIndex)")
        }
    }
        
    
    func loadSounds() {
        if let positiveSoundURL = Bundle.main.url(forResource: "positive", withExtension: "mp3"),
           let negativeSoundURL = Bundle.main.url(forResource: "negative", withExtension: "mp3") {
            do {
                // Assign to the variables directly
                let loadedPositiveSound = try AVAudioPlayer(contentsOf: positiveSoundURL)
                let loadedNegativeSound = try AVAudioPlayer(contentsOf: negativeSoundURL)
                
                // Use DispatchQueue.main.async to update the properties
                DispatchQueue.main.async {
                    self.positiveSound = loadedPositiveSound
                    self.negativeSound = loadedNegativeSound
                }
            } catch {
                print("Error loading sounds: \(error)")
            }
        }
    }

    func playPositiveSound() {
        if let soundURL = Bundle.main.url(forResource: "payment_success", withExtension: "caf") {
               do {
                   paymentSuccessPlayer = try AVAudioPlayer(contentsOf: soundURL)
                   paymentSuccessPlayer?.play()
               } catch {
                   print("Error playing payment success sound: \(error)")
               }
           }
    }

    func playNegativeSound() {
        // Play a negative system sound
        AudioServicesPlaySystemSound(1006) // Example: 1006 is the sound ID for a "Tock" sound
    }
    
    func triggerHapticFeedback(isPositive: Bool) {
        if isPositive {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        } else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)  // You can customize this for different types of vibrations
        }
    }
    
    func skipTask() {
        guard currentIndex < taskInstances.count else { return }
        
        let taskInstance = taskInstances[currentIndex]
        
        // Add the full estimated duration of the task to overUnderTime when skipped
        sharedTaskManager.overUnderTime += TimeInterval(taskInstance.task.minDuration)
        
        // Mark task as skipped and proceed to the next
        taskInstances[currentIndex].isCompleted = true
        currentIndex += 1
        if currentIndex < taskInstances.count {
            startNextTask()
        }
    }

    func comeBackToThis() {
        guard currentIndex < taskInstances.count - 1 else { return }
        
        let currentTask = taskInstances[currentIndex]
        let targetIndex = min(currentIndex + 3, taskInstances.count - 1)

        taskInstances.remove(at: currentIndex)
        taskInstances.insert(currentTask, at: targetIndex)

        startNextTask()
    }
 
    func scrollToActiveTask(using proxy: ScrollViewProxy) {
        // Scroll to the currently active task
        withAnimation {
            proxy.scrollTo(currentIndex, anchor: .top)
        }
    }
    // Your existing methods (setupRoutine, startNextTask, completeCurrentTask, etc.)

    
    func validateTaskOrder() -> Bool {
        // Example validation logic:
        // You can implement more complex checks depending on the business logic
        let valid = true // Replace this with actual validation logic
        print("Validation result: \(valid ? "Success" : "Failure")")
        return valid
    }
    
    func moveTask(from source: IndexSet, to destination: Int) {
        withAnimation {
            // Perform the move operation with animation
            taskInstances.move(fromOffsets: source, toOffset: destination)
            
            // Force a state update to refresh the list after the move
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                handleTaskReorder(source: source, destination: destination)
            }
        }
    }
    
    func handleTaskReorder(source: IndexSet, destination: Int) {
        print("Handling task reorder: source=\(source), destination=\(destination)")
        
        isMoving = true

        // Adjust the currentIndex based on the move
        if let sourceIndex = source.first {
            if currentIndex == sourceIndex {
                currentIndex = destination <= currentIndex ? destination : destination - 1
                print("Current index after move: \(currentIndex)")
                startNextTask()
            } else if destination <= currentIndex && source.contains(currentIndex) {
                currentIndex -= 1
            } else if destination > currentIndex && source.contains(currentIndex) {
                currentIndex += 1
            }
            print("Current index adjusted: \(currentIndex)")
        }

        // Update the sharedTaskManager and refresh UI immediately
        sharedTaskManager.calculateTotalTime()
        updateEstimatedFinishingTimeIfNeeded()
        updateProgress()

        isMoving = false
    }
    
    func setupRoutine() {
        taskInstances = tasks.map { TaskInstance(task: $0) }
        reinitializeSharedTaskManager()
        
        lastOverUnderMinuteThreshold = 0
        estimatedFinishingTime = sharedTaskManager.expectedEndTime
        originalFinishingTime = estimatedFinishingTime  // Set the original finishing time
        updateProgress()
        print("Initial EFT: \(formattedDate(estimatedFinishingTime) ?? "N/A")")
        print("Original Finishing Time: \(formattedDate(originalFinishingTime) ?? "N/A")")
    }

    
    func startNextTask() {
            guard currentIndex < taskInstances.count else { return }
            
            let taskInstance = taskInstances[currentIndex]
            let startTime = Date()
            
            // Store the start time both places it's needed
            taskInstances[currentIndex].startTime = startTime
            if currentIndex < sharedTaskManager.tasks.count {
                sharedTaskManager.tasks[currentIndex].startTime = startTime
            }
            
            // Calculate expected end time
            let expectedEndTime = startTime.addingTimeInterval(TimeInterval(taskInstance.task.minDuration))
            taskInstances[currentIndex].expectedEndTime = expectedEndTime
            
            timeRemaining = TimeInterval(taskInstance.task.minDuration)
            overTime = 0
            startTimer()
            print("Starting task: \(taskInstance.task.taskName)")
        }
    
    func completeCurrentTask() {
            guard currentIndex < taskInstances.count else { return }
            
            let taskInstance = taskInstances[currentIndex]
            print("Completing task: \(taskInstance.task.taskName)")
            
            lastCompletedTask = taskInstance
            lastCompletedTaskIndex = currentIndex
            
            taskInstances[currentIndex].isCompleted = true
            let completionTime = Date()
            
            // Calculate time difference based on actual vs planned duration
            if let startTime = taskInstance.startTime {
                let actualDuration = completionTime.timeIntervalSince(startTime)
                let plannedDuration = TimeInterval(taskInstance.task.minDuration)
                lastTimeDifference = plannedDuration - actualDuration
                
                // Update the over/under time calculation
                if actualDuration < plannedDuration {
                    // Completed faster than planned - we're ahead
                    sharedTaskManager.overUnderTime += (plannedDuration - actualDuration)
                } else {
                    // Took longer than planned - we're behind
                    sharedTaskManager.overUnderTime -= (actualDuration - plannedDuration)
                }
                
                print("Task completed: Planned=\(plannedDuration)s, Actual=\(actualDuration)s, Over/Under=\(sharedTaskManager.overUnderTime)s")
            }
            
            updateEstimatedFinishingTimeIfNeeded()
            updateProgress()
            
            timer?.invalidate()
            
            currentIndex += 1
            if currentIndex < taskInstances.count {
                startNextTask()
            }
            
            playPositiveSound()
            triggerHapticFeedback(isPositive: true)
        }

    

    
    func startTimer() {
        timer?.invalidate()
        var hasVibrated = false

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
                // No change to over/under while the task is running within its time
            } else {
                self.overTime += 1
                self.sharedTaskManager.overUnderTime -= 1  // Losing time when overdue
                self.updateEstimatedFinishingTimeIfNeeded()

                if !hasVibrated {
                    self.triggerHapticFeedback(isPositive: false)
                    self.playNegativeSound()
                    hasVibrated = true
                }
            }
            print("Time remaining: \(self.timeRemaining), Over time: \(self.overTime), Over/Under Time: \(self.sharedTaskManager.overUnderTime)")
        }
    }
    
    func updateEstimatedFinishingTimeIfNeeded() {
        let currentThreshold = Int(sharedTaskManager.overUnderTime / 60)
        if currentThreshold != lastOverUnderMinuteThreshold {
            sharedTaskManager.calculateExpectedEndTime(from: Date())
            estimatedFinishingTime = sharedTaskManager.expectedEndTime
            lastOverUnderMinuteThreshold = currentThreshold
            print("Updated EFT: \(formattedDate(estimatedFinishingTime) ?? "N/A")")
        }
    }
    
    func updateProgress() {
        let completedTime = taskInstances.prefix(currentIndex).reduce(0) { $0 + TimeInterval($1.task.minDuration) }
        let totalTime = taskInstances.reduce(0) { $0 + TimeInterval($1.task.minDuration) }
        progress = totalTime > 0 ? completedTime / totalTime : 0
    }
    
   
    
    func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .short
        return dateFormatter.string(from: date)
    }

    func formattedTaskDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    
    func formattedOverUnderTime(_ duration: TimeInterval) -> String {
        let minutes = Int(abs(duration)) / 60
        let seconds = Int(abs(duration)) % 60
        if duration == 0 {
            return "On schedule!"
        } else {
            let sign = duration >= 0 ? "ahead of schedule" : "behind schedule"
            return "\(minutes)m \(seconds < 10 ? "0" : "")\(seconds)s \(sign)"
        }
    }
}
