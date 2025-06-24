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
    
    var canDelayCurrentTask: Bool {
        return currentTaskIndex >= 0 && currentTaskIndex < tasks.count - 1
    }
    
    init(tasks: [TempTask]) {
        self.tasks = tasks
        self.totalRoutineDuration = tasks.reduce(0) { $0 + TimeInterval($1.duration * 60) }
        startRoutine()
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
            remainingTimeString = "00:00"
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.timerTick()
        }
    }
    
    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    private func timerTick() {
        remainingTime -= 1
        
        if remainingTime <= 0 && !isOverrun {
            isOverrun = true
        }
        
        updateRemainingTimeDisplay()
    }
    
    func markTaskComplete() {
        pauseTimer()
        
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
        }
    }
    
    func skipToNextTask() {
        markTaskComplete()
    }
    
    func delayCurrentTask(by minutes: Int) {
        remainingTime += TimeInterval(minutes * 60)
        currentTaskDuration += TimeInterval(minutes * 60)
        totalRoutineDuration += TimeInterval(minutes * 60)
        updateRemainingTimeDisplay()
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
    
    deinit {
        timer?.invalidate()
    }
}