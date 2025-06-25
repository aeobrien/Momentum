import Foundation
import SwiftUI

// Temporary task model that doesn't rely on Core Data
struct TempTask {
    let id = UUID()
    let name: String
    let duration: Int // in minutes
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
    
    private(set) var tasks: [TempTask]
    private(set) var currentTaskIndex: Int = -1
    private var timer: Timer?
    private var remainingTime: TimeInterval = 0
    private var currentTaskDuration: TimeInterval = 0
    private var scheduleOffset: TimeInterval = 0
    private var startTime: Date? = nil
    private var lastOffsetUpdateTime: Date? = nil
    
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
        self.tasks = tasks
        self.totalRoutineDuration = tasks.reduce(0) { $0 + TimeInterval($1.duration * 60) }
        self.originalFinishingTime = Date().addingTimeInterval(totalRoutineDuration)
        startRoutine()
        updateScheduleOffsetString()
        updateEstimatedFinishingTimeString()
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
        
        updateRemainingTimeDisplay()
        
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
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.timerTick()
        }
    }
    
    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        startTime = nil
        lastOffsetUpdateTime = nil
    }
    
    private func timerTick() {
        remainingTime -= 1
        
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
    
    deinit {
        timer?.invalidate()
    }
}