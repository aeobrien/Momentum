import Foundation
import SwiftUI
import Combine
import OSLog
import CoreData

// Temporary task model that doesn't rely on Core Data
struct TempTask {
    let id = UUID()
    let name: String
    let duration: Int // in minutes
    let originalTaskUUID: UUID? // Reference to original CDTask if from existing
    let isFromExisting: Bool
    
    init(name: String, duration: Int, originalTaskUUID: UUID? = nil, isFromExisting: Bool = false) {
        self.name = name
        self.duration = duration
        self.originalTaskUUID = originalTaskUUID
        self.isFromExisting = isFromExisting
    }
}

// Background task state for temporary routines
struct TempBackgroundTaskState: Identifiable {
    let id = UUID()
    let task: TempTask
    let taskIndex: Int
    var remainingTime: TimeInterval
    var isRunning: Bool = true
    var timer: Timer?
}

// Modified RoutineRunner for temporary routines
class TempRoutineRunner: ObservableObject {
    @Published var currentTaskName: String = "Loading..."
    @Published var remainingTimeString: String = "00:00"
    @Published var isRunning: Bool = false
    @Published var scheduleOffsetString: String = "On schedule"
    @Published var estimatedFinishingTimeString: String = ""
    @Published private(set) var originalFinishingTime: Date = Date()
    @Published var isRoutineComplete: Bool = false
    @Published var isOverrun: Bool = false
    @Published var nextTaskName: String? = nil
    @Published var totalRoutineDuration: TimeInterval = 0
    @Published var completedDuration: TimeInterval = 0
    @Published var isHandlingInterruption: Bool = false
    @Published var backgroundTasks: [TempBackgroundTaskState] = []
    @Published var canMoveToBackground: Bool = false
    @Published var completedTaskIndices: Set<Int> = []
    
    private(set) var tasks: [TempTask]
    private(set) var currentTaskIndex: Int = -1
    private var timer: AnyCancellable?
    private var remainingTime: TimeInterval = 0
    private var currentTaskDuration: TimeInterval = 0
    private var scheduleOffset: TimeInterval = 0
    private var startTime: Date? = nil
    private var lastOffsetUpdateTime: Date? = nil
    private var interruptedTaskState: (taskIndex: Int, remainingTime: TimeInterval)?
    private var backgroundEnterTime: Date? = nil
    private var remainingTimeOnPause: TimeInterval? = nil
    private var timeToCountDownAtStart: TimeInterval = 0
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TempRoutineRunner")
    
    var progressFraction: Double {
        guard totalRoutineDuration > 0 else { return 0.0 }
        return min(completedDuration / totalRoutineDuration, 1.0)
    }
    
    var progressTaskString: String {
        guard currentTaskIndex >= 0 && currentTaskIndex < tasks.count else {
            if isRoutineComplete {
                return "Tasks Complete"
            } else if tasks.isEmpty {
                return "No Tasks"
            } else {
                return "Task 1 / \(tasks.count)"
            }
        }
        return "Task \(currentTaskIndex + 1) / \(tasks.count)"
    }
    
    @Published var taskProgressFraction: Double = 0.0
    
    var canDelayCurrentTask: Bool {
        return currentTaskIndex >= 0 && currentTaskIndex < tasks.count - 1
    }
    
    init(tasks: [TempTask]) {
        logger.info("TempRoutineRunner init with \(tasks.count) tasks")
        self.tasks = tasks
        self.totalRoutineDuration = tasks.reduce(0) { $0 + TimeInterval($1.duration * 60) }
        self.originalFinishingTime = Date().addingTimeInterval(totalRoutineDuration)
        logger.info("About to start routine in init")
        startRoutine()
        updateScheduleOffsetString()
        updateEstimatedFinishingTimeString()
        logger.info("TempRoutineRunner init complete")
    }
    
    private func startRoutine() {
        guard !tasks.isEmpty else { return }
        currentTaskIndex = 0
        configureCurrentTask()
    }
    
    private func configureCurrentTask() {
        guard currentTaskIndex >= 0 && currentTaskIndex < tasks.count else { return }
        
        let task = tasks[currentTaskIndex]
        currentTaskName = task.name
        currentTaskDuration = TimeInterval(task.duration * 60)
        remainingTime = currentTaskDuration
        isOverrun = false
        taskProgressFraction = 0.0 // Reset task progress
        remainingTimeOnPause = nil // Clear any stored pause time from previous task
        
        updateRemainingTimeDisplay()
        updateCanMoveToBackground()
        
        // Set next task name
        if currentTaskIndex < tasks.count - 1 {
            nextTaskName = tasks[currentTaskIndex + 1].name
        } else {
            nextTaskName = nil
        }
    }
    
    private func updateRemainingTimeDisplay() {
        if isOverrun {
            // Show negative time during overrun
            let overrunTime = abs(remainingTime)
            let minutes = Int(overrunTime) / 60
            let seconds = Int(overrunTime) % 60
            remainingTimeString = String(format: "-%02d:%02d", minutes, seconds)
        } else {
            let minutes = Int(remainingTime) / 60
            let seconds = Int(remainingTime) % 60
            remainingTimeString = String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    func toggleTimer() {
        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
        isRunning = true
        
        // Check if we're resuming from a pause (including background)
        if let pausedTime = remainingTimeOnPause {
            // Resuming from pause
            timeToCountDownAtStart = pausedTime
            remainingTimeOnPause = nil
            logger.debug("Starting timer from paused time: \(pausedTime)s")
        } else {
            // Starting fresh (use full duration or current remaining time)
            timeToCountDownAtStart = isOverrun ? 0 : remainingTime
            logger.debug("Starting timer fresh: \(self.timeToCountDownAtStart)s")
        }
        
        startTime = Date()
        
        // Setup the Combine timer to fire every second
        timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect().sink { [weak self] fireDate in
            guard let self = self, self.isRunning else { return }
            
            let elapsedTime = fireDate.timeIntervalSince(self.startTime ?? fireDate)
            let timeRemaining = self.timeToCountDownAtStart - elapsedTime
            
            self.remainingTime = timeRemaining
            self.timerTick()
        }
    }
    
    private func pauseTimer(isBackgrounding: Bool = false) {
        isRunning = false
        timer?.cancel()
        timer = nil
        
        // Store the remaining time when pausing
        if !isOverrun {
            remainingTimeOnPause = remainingTime
            logger.debug("Paused with remaining time: \(self.remainingTime)s")
        } else if isBackgrounding {
            // Even when overrun, store the negative remaining time for background
            remainingTimeOnPause = remainingTime
            logger.debug("Paused during overrun with time: \(self.remainingTime)s")
        }
        
        startTime = nil
        lastOffsetUpdateTime = nil
    }
    
    private func timerTick() {
        // remainingTime is already updated by the timer closure
        
        if remainingTime <= 0 && !isOverrun {
            isOverrun = true
        }
        
        // Update task progress fraction
        if currentTaskDuration > 0 {
            let elapsed = currentTaskDuration - remainingTime
            taskProgressFraction = min(max(elapsed / currentTaskDuration, 0.0), 1.0)
        }
        
        // Update schedule offset during overrun
        if isOverrun {
            let now = Date()
            if let lastUpdate = lastOffsetUpdateTime {
                let additionalOverrun = now.timeIntervalSince(lastUpdate)
                scheduleOffset += additionalOverrun
            }
            lastOffsetUpdateTime = now
            updateScheduleOffsetString()
            updateEstimatedFinishingTimeString()
        }
        
        updateRemainingTimeDisplay()
    }
    
    func markTaskComplete() {
        let wasRunning = isRunning
        pauseTimer()
        
        // Mark current task as completed
        if currentTaskIndex >= 0 {
            completedTaskIndices.insert(currentTaskIndex)
            
            // If this task is from an existing task, mark it as completed in Core Data
            let currentTask = tasks[currentTaskIndex]
            if currentTask.isFromExisting, let originalTaskUUID = currentTask.originalTaskUUID {
                markOriginalTaskComplete(uuid: originalTaskUUID)
            }
        }
        
        // Check if we're completing an interruption
        if isHandlingInterruption && tasks[currentTaskIndex].name == "Interruption" {
            // Calculate actual time spent on interruption
            var actualInterruptionTime: TimeInterval = 180 // Default to full 3 minutes
            if remainingTimeOnPause != nil {
                actualInterruptionTime = 180 - remainingTimeOnPause!
            } else if isOverrun {
                // Task went into overrun - remaining time is negative
                actualInterruptionTime = 180 - remainingTime // Since remainingTime is negative, this adds
            } else if let start = startTime {
                actualInterruptionTime = Date().timeIntervalSince(start)
            } else {
                // If timer wasn't started, use remaining time
                actualInterruptionTime = 180 - remainingTime
            }

            // Update schedule offset based on actual time vs expected 3 minutes
            let timeDifference = 180 - actualInterruptionTime
            if timeDifference > 0 {
                // Completed interruption faster than 3 minutes, gain time back
                scheduleOffset -= timeDifference
            }
            // Note: If interruption went over time, the overrun updates have already adjusted scheduleOffset

            // Update completed duration for actual time spent
            completedDuration += actualInterruptionTime

            // Update schedule displays
            updateScheduleOffsetString()
            updateEstimatedFinishingTimeString()

            // Restore the interrupted task
            restoreInterruptedTask()
            return
        }
        
        // Calculate actual completion time for schedule offset
        if isOverrun {
            let overrunAmount = abs(remainingTime)
            scheduleOffset += overrunAmount
        } else {
            // Completed early
            scheduleOffset -= remainingTime
        }
        
        // Update completed duration
        completedDuration += currentTaskDuration
        
        // Move to next task
        currentTaskIndex += 1
        
        if currentTaskIndex >= tasks.count {
            // Routine complete
            isRoutineComplete = true
            currentTaskName = "Routine Complete"
            remainingTimeString = "00:00"
        } else {
            configureCurrentTask()
            // Resume timer if it was running
            if wasRunning {
                startTimer()
            }
        }
        
        updateScheduleOffsetString()
        updateEstimatedFinishingTimeString()
    }
    
    func skipToNextTask() {
        // Check if we're skipping an interruption task
        if isHandlingInterruption && currentTaskIndex >= 0 && currentTaskIndex < tasks.count && tasks[currentTaskIndex].name == "Interruption" {
            // Calculate time spent on interruption before skipping
            var timeElapsed: TimeInterval = 0
            if remainingTimeOnPause != nil {
                timeElapsed = 180 - remainingTimeOnPause!
            } else if let start = startTime {
                timeElapsed = Date().timeIntervalSince(start)
            } else {
                timeElapsed = 180 - remainingTime
            }
            let timeSaved = 180 - timeElapsed

            // Update schedule offset - we save the time not spent on the interruption
            if timeSaved > 0 {
                scheduleOffset -= timeSaved // Reduce the behind-schedule amount
            }

            // Update completed duration for time actually spent
            completedDuration += timeElapsed

            // Pause timer
            pauseTimer()

            // Update schedule displays
            updateScheduleOffsetString()
            updateEstimatedFinishingTimeString()

            // Restore the interrupted task
            restoreInterruptedTask()
            return
        }

        // Normal skip behavior
        markTaskComplete()
    }
    
    func delayCurrentTask(by delayCount: Int = 3) {
        // Ensure index is valid and there are tasks remaining after the current one
        guard canDelayCurrentTask else { return }
        
        // Ensure delayCount is positive
        guard delayCount > 0 else { return }
        
        // Store running state
        let wasRunning = isRunning
        
        // Stop the current timer
        pauseTimer()
        
        // Reorder the tasks array
        let taskToDelay = tasks.remove(at: currentTaskIndex)
        
        // Calculate the new index, ensuring it doesn't exceed bounds
        let insertionIndex = min(currentTaskIndex + delayCount, tasks.count)
        tasks.insert(taskToDelay, at: insertionIndex)
        
        // Configure the new task at currentTaskIndex
        configureCurrentTask()
        
        // Restart the timer if it was running
        if wasRunning {
            startTimer()
        }
    }
    
    func endRoutine() {
        pauseTimer()
        isRoutineComplete = true
        currentTaskName = "Routine Ended"
        remainingTimeString = "00:00"
    }
    
    func reorderTasks(from source: IndexSet, to destination: Int) {
        // Only allow reordering of future tasks
        guard let sourceIndex = source.first,
              sourceIndex > currentTaskIndex else { return }
        
        tasks.move(fromOffsets: source, toOffset: destination)
        
        // Update next task name if needed
        if currentTaskIndex < tasks.count - 1 {
            nextTaskName = tasks[currentTaskIndex + 1].name
        }
    }
    
    private func updateScheduleOffsetString() {
        if abs(scheduleOffset) < 1 {
            scheduleOffsetString = "On schedule"
        } else {
            let absOffset = abs(scheduleOffset)
            let minutes = Int(absOffset) / 60
            let seconds = Int(absOffset) % 60
            let timeString = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
            
            if scheduleOffset > 0 {
                scheduleOffsetString = "\(timeString) behind"
            } else {
                scheduleOffsetString = "\(timeString) ahead"
            }
        }
    }
    
    private func updateEstimatedFinishingTimeString() {
        let estimatedFinish = originalFinishingTime.addingTimeInterval(scheduleOffset)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        estimatedFinishingTimeString = formatter.string(from: estimatedFinish)
    }
    
    func resetTimer() {
        pauseTimer()
        isOverrun = false
        lastOffsetUpdateTime = nil
        configureCurrentTask()
    }
    
    // MARK: - Interruption Handling
    
    func handleInterruption() {
        guard currentTaskIndex >= 0 && currentTaskIndex < tasks.count && !isRoutineComplete else { return }
        guard !isHandlingInterruption else { return }

        // Store the current task state
        interruptedTaskState = (taskIndex: currentTaskIndex, remainingTime: remainingTime)

        // Pause current timer
        pauseTimer()

        // Create interruption task
        let interruptionTask = TempTask(name: "Interruption", duration: 3)

        // Insert at current position
        tasks.insert(interruptionTask, at: currentTaskIndex)

        // Update total duration
        totalRoutineDuration += 180 // 3 minutes

        // Update schedule offset - adding an interruption puts us behind schedule
        scheduleOffset += 180 // Positive means behind schedule
        updateScheduleOffsetString()
        updateEstimatedFinishingTimeString()

        // Mark as handling interruption
        isHandlingInterruption = true

        // Configure the interruption task
        configureCurrentTask()
        startTimer()
    }
    
    private func restoreInterruptedTask() {
        guard let interruptedState = interruptedTaskState else { return }
        
        // Remove the interruption task
        if currentTaskIndex >= 0 && currentTaskIndex < tasks.count {
            tasks.remove(at: currentTaskIndex)
            totalRoutineDuration -= 180
        }
        
        // Clear interruption state
        interruptedTaskState = nil
        isHandlingInterruption = false
        
        // Restore the interrupted task
        if currentTaskIndex < tasks.count {
            configureCurrentTask()
            remainingTime = interruptedState.remainingTime
            updateRemainingTimeDisplay()
            startTimer()
        }
    }
    
    // MARK: - Background Task Handling
    
    func moveCurrentTaskToBackground() {
        guard currentTaskIndex >= 0 && currentTaskIndex < tasks.count && !isRoutineComplete else { return }
        
        // Don't allow interruption tasks to be backgrounded
        if tasks[currentTaskIndex].name == "Interruption" { return }
        
        // Create background task state
        var backgroundTask = TempBackgroundTaskState(
            task: tasks[currentTaskIndex],
            taskIndex: currentTaskIndex,
            remainingTime: remainingTime
        )
        
        // Pause current timer
        pauseTimer()
        
        // Start background timer
        startBackgroundTimer(for: &backgroundTask)
        backgroundTasks.append(backgroundTask)
        
        // Move to next task
        markTaskComplete()
        
        updateCanMoveToBackground()
    }
    
    private func startBackgroundTimer(for backgroundTask: inout TempBackgroundTaskState) {
        let taskId = backgroundTask.id
        let initialRemainingTime = backgroundTask.remainingTime
        
        backgroundTask.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let index = self.backgroundTasks.firstIndex(where: { $0.id == taskId }) else { return }
            
            self.backgroundTasks[index].remainingTime -= 1
            self.updateEstimatedFinishingTimeString()
        }
    }
    
    func completeBackgroundTask(at index: Int) {
        guard index >= 0 && index < backgroundTasks.count else { return }
        
        backgroundTasks[index].timer?.invalidate()
        backgroundTasks.remove(at: index)
        
        updateCanMoveToBackground()
    }
    
    private func updateCanMoveToBackground() {
        // Allow background tasks only if not the last task and not already have a background task
        canMoveToBackground = currentTaskIndex >= 0 && 
                             currentTaskIndex < tasks.count - 1 && 
                             backgroundTasks.isEmpty &&
                             !isRoutineComplete
    }
    
    deinit {
        timer?.cancel()
        for i in backgroundTasks.indices {
            backgroundTasks[i].timer?.invalidate()
        }
    }
    
    // MARK: - Background Handling
    
    func observeScenePhase(_ newPhase: ScenePhase) {
        logger.debug("Observing scene phase change to: \(String(describing: newPhase))")
        if isRoutineComplete {
            logger.debug("Scene phase changed, but routine is complete. No action needed.")
            return
        }
        
        switch newPhase {
        case .active:
            // App came to foreground
            logger.info("App became active.")
            // Check if we have a background entry time recorded
            if let backgroundEnterTime = backgroundEnterTime {
                // Calculate time spent in background
                let timeInBackground = Date().timeIntervalSince(backgroundEnterTime)
                logger.info("App was in background for \(timeInBackground) seconds.")
                self.backgroundEnterTime = nil // Clear the background entry time
                
                // If the timer was running when backgrounded
                if remainingTimeOnPause != nil {
                    // Adjust remaining time based on time spent in background
                    let newRemainingTime = (remainingTimeOnPause ?? currentTaskDuration) - timeInBackground
                    logger.debug("Adjusted remaining time from \(self.remainingTimeOnPause ?? -1)s to \(newRemainingTime)s")
                    
                    if newRemainingTime > 0 {
                        // Time remaining, resume timer from adjusted time
                        remainingTimeOnPause = newRemainingTime
                        startTimer() // Will use remainingTimeOnPause
                        logger.info("Resuming timer after background.")
                    } else {
                        // Time ran out while in background
                        logger.info("Time expired while in background.")
                        // Mark overrun
                        isOverrun = true
                        
                        let overrunDuration = abs(newRemainingTime)
                        logger.info("Overrun by \(overrunDuration) seconds.")
                        
                        // Adjust schedule offset for the overrun
                        scheduleOffset += overrunDuration
                        updateScheduleOffsetString()
                        updateEstimatedFinishingTimeString()
                        
                        // Update display to show current overrun time
                        remainingTime = -overrunDuration
                        updateRemainingTimeDisplay()
                        
                        // Update task progress fraction
                        if currentTaskDuration > 0 {
                            let totalElapsed = currentTaskDuration + overrunDuration
                            taskProgressFraction = min(max(totalElapsed / currentTaskDuration, 0.0), 1.0)
                        }
                        
                        // Start timer in overrun mode
                        remainingTimeOnPause = -overrunDuration
                        startTimer()
                    }
                }
            }
            
        case .inactive:
            logger.info("App became inactive.")
            // Usually happens briefly during app switching
            
        case .background:
            logger.info("App entered background.")
            if isRunning {
                // Record the time we entered the background
                backgroundEnterTime = Date()
                logger.debug("Recorded background enter time")
                // Pause the timer, indicating it's due to backgrounding
                pauseTimer(isBackgrounding: true)
            } else {
                // If timer wasn't running, still record background time
                backgroundEnterTime = Date()
                logger.debug("App entered background while timer was paused")
            }
            
        @unknown default:
            logger.warning("Unknown scene phase encountered")
            break
        }
    }
    
    // MARK: - Core Data Integration
    
    private func markOriginalTaskComplete(uuid: UUID) {
        // Use the DataStoreManager's context
        let context = DataStoreManager.shared.viewContext
        
        // Fetch the task with the given UUID
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        
        do {
            let tasks = try context.fetch(fetchRequest)
            if let task = tasks.first {
                // Mark the task as completed
                task.lastCompleted = Date()
                
                // Save the context
                try context.save()
                
                logger.info("Marked original task '\(task.taskName ?? "")' as completed")
            } else {
                logger.warning("Could not find task with UUID: \(uuid)")
            }
        } catch {
            logger.error("Error marking task as complete: \(error.localizedDescription)")
        }
    }
}