// RoutineRunner.swift
import Foundation
import AVFoundation
import UserNotifications
import Combine
import UIKit
import SwiftUI
import OSLog
import CoreData

/// Manages the state and logic for running a routine, including the timer.
// Renamed from RoutineRunnerViewModel to RoutineRunner
class RoutineRunner: ObservableObject {

    // MARK: - Published Properties (for UI updates)

    /// The name of the task currently being timed. Returns "Routine Complete" if done.
    @Published var currentTaskName: String = "Loading..."
    /// The remaining time for the current task, formatted as a string (e.g., "01:23"). Shows "00:00" during overrun.
    @Published var remainingTimeString: String = "00:00"
    /// Indicates whether the timer is currently running.
    @Published var isRunning: Bool = false
    /// The formatted string describing the schedule status (e.g., "1:30 ahead of schedule").
    @Published var scheduleOffsetString: String = "On schedule"
    /// Indicates if the routine is finished.
    @Published var isRoutineComplete: Bool = false
    /// Tracks if the timer for the current task has hit 00:00 and is now counting late time.
    @Published var isOverrun: Bool = false // Made public for view access
    /// The name of the next task in the schedule, or nil if the current task is the last.
    @Published var nextTaskName: String? = nil

    // MARK: - Progress Properties (Published for UI)
    /// The total allocated time for all tasks in the routine (in seconds).
    @Published private(set) var totalRoutineDuration: TimeInterval = 0
    /// The cumulative allocated time for completed tasks (in seconds).
    @Published private(set) var completedDuration: TimeInterval = 0

    // MARK: - Progress Computed Properties (for View)
    /// The fraction of the routine completed, based on allocated time (0.0 to 1.0).
    var progressFraction: Double {
        guard totalRoutineDuration > 0 else { return 0.0 }
        // Ensure progress doesn't exceed 1.0, even with potential floating point inaccuracies
        return min(completedDuration / totalRoutineDuration, 1.0)
    }

    /// A string indicating the current task number out of the total (e.g., "Task 5 / 12").
    var progressTaskString: String {
        guard currentTaskIndex >= 0 && currentTaskIndex < scheduledTasks.count else {
            // Handle cases where no task is active (e.g., before start or after completion)
            if isRoutineComplete {
                return "Tasks Complete"
            } else if scheduledTasks.isEmpty {
                return "No Tasks"
            } else {
                // If preparing the first task but not yet started
                return "Task 1 / \(scheduledTasks.count)"
            }
        }
        return "Task \(currentTaskIndex + 1) / \(scheduledTasks.count)"
    }

    // MARK: - Core Data & Routine Properties

    /// The Core Data managed object context.
    private let context: NSManagedObjectContext
    /// The specific routine being run. (No longer the primary source of tasks)
    let routine: CDRoutine // Changed back from private let
    /// The pre-processed, ordered list of tasks to run with their allocated durations.
    var scheduledTasks: [ScheduledTask]
    /// The list of tasks (CDRoutineTask) in the current routine, sorted by order.
    // private var routineTasks: [CDRoutineTask] = [] // Replaced by scheduledTasks
    /// The index of the currently active task in the `scheduledTasks` array. -1 if not started or complete.
    private(set) var currentTaskIndex: Int = -1

    // MARK: - Computed Properties for UI State

    /// Indicates if the currently active task can be delayed (i.e., it's not the last task).
    var canDelayCurrentTask: Bool {
        // Can only delay if the index is valid AND it's not the last task in the current schedule
        return currentTaskIndex >= 0 && currentTaskIndex < scheduledTasks.count - 1
    }

    // MARK: - Timer Properties

    /// The timer instance that fires every second.
    private var timer: AnyCancellable?
    /// The total duration of the *current* task in seconds.
    private var currentTaskDuration: TimeInterval = 0
    /// The exact time when the timer was last started or resumed.
    private var startTime: Date? = nil
    /// The time remaining when the timer was paused. Stores actual time left, not overrun.
    private var remainingTimeOnPause: TimeInterval? = nil
    /// Timestamp of when the app entered the background. Used to calculate elapsed time.
    private var backgroundEnterTime: Date? = nil
    /// The effective time the current timer started counting down from (either full duration or remaining time on resume/background).
    private var timeToCountDownAtStart: TimeInterval = 0
    /// Timestamp of the last time the schedule offset was updated due to overrun.
    private var lastOffsetUpdateTime: Date? = nil


    // MARK: - Schedule Offset Properties

    /// Tracks the total deviation from the scheduled completion times (in seconds).
    /// Negative means ahead of schedule, Positive means behind schedule.
    private var scheduleOffset: TimeInterval = 0
    
    /// The original finishing time selected when the routine was started.
    @Published private(set) var originalFinishingTime: Date = Date()
    
    /// The estimated finishing time based on the original time plus/minus the schedule offset.
    @Published var estimatedFinishingTimeString: String = ""

    // MARK: - Logging

    /// Logger for detailed debug and informational messages within the view model.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineRunner") // Changed category
    /// Formatter for adding precise timestamps to logs.
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS" // Hours:Minutes:Seconds.Milliseconds
        return formatter
    }()

    /// Helper to get the current formatted time string for logging.
    private func logTime() -> String {
        return Self.logDateFormatter.string(from: Date())
    }

    // MARK: - Initialization

    /// Initializes the Runner with the managed object context, the routine context, and the pre-calculated schedule.
    /// - Parameter context: The NSManagedObjectContext for Core Data operations.
    /// - Parameter routine: The CDRoutine this schedule belongs to (for context like name).
    /// - Parameter schedule: The ordered list of ScheduledTask objects to run.
    /// - Parameter originalFinishingTime: The original finishing time selected when the routine was started.
    init(context: NSManagedObjectContext, routine: CDRoutine, schedule: [ScheduledTask], originalFinishingTime: Date = Date()) {
        // Find the routine associated with the first task for context (e.g., name)
        // This assumes schedule is not empty and tasks belong to the same routine.
        // guard let firstTask = schedule.first?.task, let routine = firstTask.routine else {
            // Fallback or error handling if schedule is empty or task has no routine reference.
        //    fatalError("Cannot initialize RoutineRunner: Schedule is empty or first task has no routine reference.")
        // }

        self.context = context
        self.scheduledTasks = schedule
        self.routine = routine // Use the passed-in routine
        self.originalFinishingTime = originalFinishingTime

        // Calculate total duration
        self.totalRoutineDuration = schedule.reduce(0) { $0 + $1.allocatedDuration }
        logger.info("Total calculated routine duration: \(self.totalRoutineDuration / 60, format: .fixed(precision: 1)) minutes.")

        logger.info("RoutineRunner initialized for routine: \(routine.name ?? "Unnamed Routine") with \(schedule.count) scheduled tasks.")
        // fetchAndSortTasks() // No longer needed - schedule is provided
        prepareFirstTask() // Set up the first task from the schedule
        updateScheduleOffsetString() // Initialize offset string
        updateEstimatedFinishingTimeString() // Initialize estimated finishing time
        // Initialize completed duration (starts at 0)
        updateCompletedDuration()
    }

    /// Fetches the CDRoutineTask entities from the provided CDRoutine and sorts them by their 'order' attribute.
    // private func fetchAndSortTasks() { ... } // No longer needed


    /// Sets up the very first task without starting the timer.
    private func prepareFirstTask() {
        guard !scheduledTasks.isEmpty else {
            logger.warning("Prepare first task called, but no tasks in the provided schedule for routine '\(self.routine.name ?? "Unnamed")'.")
            if currentTaskName == "Loading..." {
                 currentTaskName = "No Tasks Scheduled"
            }
            isRoutineComplete = true
            return
        }
        if currentTaskIndex == -1 && !isRoutineComplete {
            currentTaskIndex = 0
            logger.info("Preparing first task.")
            configureTask(at: currentTaskIndex)
        }
    }

    // MARK: - Task Management

    /// Configures the view model state for the task at the given index. Does not start the timer.
    /// - Parameter index: The index of the task in the `scheduledTasks` array.
    private func configureTask(at index: Int) {
        guard index >= 0 && index < scheduledTasks.count else {
            logger.error("Configure task called with invalid index: \(index). Scheduled tasks count: \(self.scheduledTasks.count)")
            completeRoutine() // Mark routine complete if index is invalid
            return
        }

        let scheduled = scheduledTasks[index]
        let task = scheduled.task // Access the CDTask

        currentTaskName = task.taskName ?? "Unnamed Task"
        // IMPORTANT: Use allocatedDuration from ScheduledTask, not minDuration
        currentTaskDuration = scheduled.allocatedDuration
        logger.info("Configuring task \(index + 1)/\(self.scheduledTasks.count): '\(self.currentTaskName, privacy: .public)', Allocated Duration: \(scheduled.allocatedDuration / 60, format: .fixed(precision: 1))m")

        // Reset timer state variables for the new task
        timer?.cancel()
        timer = nil
        isRunning = false
        startTime = nil
        remainingTimeOnPause = nil
        backgroundEnterTime = nil
        isOverrun = false
        lastOffsetUpdateTime = nil
        DispatchQueue.main.async { self.isOverrun = false }

        updateRemainingTimeDisplay(currentTaskDuration) // Show full (allocated) duration initially
        updateScheduleOffsetString() // Update offset string display
        updateEstimatedFinishingTimeString() // Update estimated finishing time

        // Update the next task name
        let nextIndex = index + 1
        if nextIndex < scheduledTasks.count {
            self.nextTaskName = scheduledTasks[nextIndex].task.taskName
            logger.debug("Next task set to: \(self.nextTaskName ?? "None")")
        } else {
            self.nextTaskName = nil // No more tasks
            logger.debug("Current task is the last one. nextTaskName set to nil.")
        }

        // Update completed duration whenever a new task is configured
        updateCompletedDuration()
    }

    /// Advances to the next task in the routine.
    private func advanceToNextTask() {
        logger.debug("Attempting to advance to the next task from index \(self.currentTaskIndex).")
        guard self.currentTaskIndex >= 0 else {
            logger.warning("Cannot advance task, current index is invalid (\(self.currentTaskIndex)).")
            if !self.scheduledTasks.isEmpty {
                 self.prepareFirstTask()
            }
            return
        }

        // Update completed duration *before* incrementing the index
        updateCompletedDuration() 
        
        let nextIndex = self.currentTaskIndex + 1
        if nextIndex < self.scheduledTasks.count {
            logger.info("Advancing to task \(nextIndex + 1).)")
            self.currentTaskIndex = nextIndex
            self.configureTask(at: self.currentTaskIndex)
            self.startTimer()
        } else {
            logger.info("Advanced past the last task. Routine complete.")
            self.completeRoutine()
        }
    }

    /// Marks the routine as complete and updates the UI state.
    /// - Parameter errorMessage: Optional message to display instead of "Routine Complete!".
    private func completeRoutine(errorMessage: String? = nil) {
        logger.log(level: .info, "Routine '\(self.routine.name ?? "Unnamed", privacy: .public)' completed. Final schedule offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
        self.currentTaskIndex = -1 // Reset index
        // Update published properties on the main thread
        DispatchQueue.main.async {
            self.currentTaskName = errorMessage ?? "Routine Complete!"
            self.remainingTimeString = "--:--" // Indicate no timer
            self.isRunning = false
            self.isRoutineComplete = true // Update published property
            self.isOverrun = false
            self.nextTaskName = nil // Clear next task name on completion
        }
        timer?.cancel()
        timer = nil
        // Keep the final schedule offset string displayed
         self.updateRoutineMetadata()

        // Ensure progress reflects completion
        self.completedDuration = self.totalRoutineDuration
        self.currentTaskIndex = -1 // Explicitly set index to -1 on completion for progressTaskString

        // SAVE context ONCE after all updates
        self.saveContext()

        // Update published properties on the main thread
        DispatchQueue.main.async {
            // ... existing UI updates ...
             self.objectWillChange.send() // Force update if needed
        }
    }

    /// Updates the routine's metadata (e.g., lastUsed) in Core Data.
    private func updateRoutineMetadata() {
        logger.debug("Updating metadata for routine: \(self.routine.name ?? "Unnamed", privacy: .public)")
        self.routine.lastUsed = Date() // Update last used timestamp
        // Increment completion count? Depends on requirements
        // routine.totalCompletions += 1

        // REMOVED Save from here
        // do {
        //     if self.context.hasChanges {
        //         try self.context.save()
        //         logger.info("Successfully saved updated metadata for routine \''.")
        //     }
        // } catch {
        //     logger.error("Failed to save routine metadata changes: \(error.localizedDescription)")
        // }
    }


    // MARK: - User Actions

    /// Called when the user taps the "Done" button. Marks the current task complete and moves to the next.
    func markTaskComplete() {
        guard self.currentTaskIndex != -1 && self.currentTaskIndex < self.scheduledTasks.count && !self.isRoutineComplete else {
            logger.warning("Mark complete called but no task is active or routine is finished.")
            return
        }
        let completedTask = self.scheduledTasks[self.currentTaskIndex].task
        let completedTaskName = completedTask.taskName ?? "Unnamed Task"
        logger.info("User marked task '\(completedTaskName, privacy: .public)' complete.")

        timer?.cancel() // Stop the timer
        timer = nil
        isRunning = false
        // DON'T clear startTime yet - we need it for duration calculation!

        // Calculate deviation based on allocated duration
        let expectedDuration = self.currentTaskDuration // This is now the allocated duration
        var actualDuration: TimeInterval = 0
        if let pauseTime = self.remainingTimeOnPause {
            actualDuration = expectedDuration - pauseTime
        } else if self.isOverrun {
            let intendedEndTime = (startTime ?? Date()).addingTimeInterval(self.timeToCountDownAtStart)
            let timeSinceIntendedEnd = Date().timeIntervalSince(intendedEndTime)
            actualDuration = expectedDuration + timeSinceIntendedEnd
        } else if let start = startTime {
            actualDuration = Date().timeIntervalSince(start)
            // Ensure we record at least 1 second if the task was started
            if actualDuration < 1.0 {
                actualDuration = 1.0
            }
        } else {
            // If no start time recorded, use a default minimum duration
            actualDuration = 1.0
        }

        let deviation = actualDuration - expectedDuration
        self.scheduleOffset += deviation
        logger.info("Task '\(completedTaskName, privacy: .public)' completed. Duration: \(actualDuration, format: .fixed(precision: 1))s (Expected: \(expectedDuration, format: .fixed(precision: 1))s). Deviation: \(deviation, format: .fixed(precision: 1))s. New total offset: \(self.scheduleOffset, format: .fixed(precision: 1))s.")

        self.updateScheduleOffsetString()
        self.updateEstimatedFinishingTimeString()
        
        // NOW we can clear the timing state
        self.startTime = nil
        self.remainingTimeOnPause = nil
        self.isOverrun = false
        self.lastOffsetUpdateTime = nil
        DispatchQueue.main.async { [weak self] in
           guard let self = self else { return }
           self.isRunning = false
           self.objectWillChange.send()
        }

        self.updateTaskCompletionStatus() // Updates lastCompleted & nextDueDate for the CDTask in memory
        
        // Record completion time if tracking is enabled
        if completedTask.shouldTrackAverageTime {
            recordCompletionTime(for: completedTask, duration: actualDuration)
        }

        // SAVE context ONCE after task status update
        self.saveContext()

        // Update completed duration *before* advancing index
        // Add the duration of the task *just completed* to the sum
        // CAPTURE the index BEFORE the async block
        let indexForDurationCalculation = self.currentTaskIndex
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Use the captured index here
            let previouslyCompletedDuration = self.scheduledTasks.prefix(indexForDurationCalculation).reduce(0) { $0 + $1.allocatedDuration }
            let newCompletedDuration = previouslyCompletedDuration + expectedDuration // Use expectedDuration here
            if self.completedDuration != newCompletedDuration {
                 self.completedDuration = newCompletedDuration
                 self.logger.debug("Updated completed duration after task completion: \(self.completedDuration / 60, format: .fixed(precision: 1))m")
                 self.objectWillChange.send()
             }
        }

        // Advance *after* calculation and updates
        self.advanceToNextTask()
    }

    /// Skips the current task, updating schedule offset based on time saved.
    func skipCurrentTask() {
        guard self.currentTaskIndex != -1 && self.currentTaskIndex < self.scheduledTasks.count && !self.isRoutineComplete else {
            logger.warning("Skip called but no task is active or routine is finished.")
            return
        }
        let skippedTask = self.scheduledTasks[self.currentTaskIndex].task
        let skippedTaskName = skippedTask.taskName ?? "Unnamed Task"
        logger.info("User skipped task '\(skippedTaskName, privacy: .public)'.")

        // Calculate time saved by skipping
        let expectedDuration = self.currentTaskDuration // This is the allocated duration
        var timeElapsed: TimeInterval = 0
        
        if let pauseTime = self.remainingTimeOnPause {
            // Task was paused, calculate elapsed time from remaining
            timeElapsed = expectedDuration - pauseTime
        } else if let start = startTime {
            // Task was running, calculate elapsed time
            timeElapsed = Date().timeIntervalSince(start)
        } else {
            // Task was never started, elapsed time is 0
            timeElapsed = 0
        }
        
        let timeSaved = expectedDuration - timeElapsed
        
        // Update schedule offset - negative means ahead of schedule
        self.scheduleOffset -= timeSaved
        logger.info("Task '\(skippedTaskName, privacy: .public)' skipped. Time elapsed: \(timeElapsed, format: .fixed(precision: 1))s, Time saved: \(timeSaved, format: .fixed(precision: 1))s. New total offset: \(self.scheduleOffset, format: .fixed(precision: 1))s.")
        
        self.updateScheduleOffsetString()
        self.updateEstimatedFinishingTimeString()

        // Stop timer and reset state
        timer?.cancel()
        timer = nil
        isRunning = false
        startTime = nil
        remainingTimeOnPause = nil
        isOverrun = false
        lastOffsetUpdateTime = nil
        DispatchQueue.main.async { [weak self] in
           guard let self = self else { return }
           self.isRunning = false
           self.objectWillChange.send()
        }

        // Update completed duration *before* advancing index
        // Treat skipped task's duration as 'completed' for progress calculation
        // CAPTURE the index BEFORE the async block
        let indexForDurationCalculation = self.currentTaskIndex
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Use the captured index here
            let previouslyCompletedDuration = self.scheduledTasks.prefix(indexForDurationCalculation).reduce(0) { $0 + $1.allocatedDuration }
            let skippedTaskDuration = self.currentTaskDuration // Duration of the task being skipped
            let newCompletedDuration = previouslyCompletedDuration + skippedTaskDuration
            if self.completedDuration != newCompletedDuration {
                 self.completedDuration = newCompletedDuration
                 self.logger.debug("Updated completed duration after task skip: \(self.completedDuration / 60, format: .fixed(precision: 1))m")
                 self.objectWillChange.send()
             }
        }

        // Advance *after* update
        self.advanceToNextTask()
    }

    /// Updates the completion status (e.g., lastCompleted date) of the current task in Core Data.
    private func updateTaskCompletionStatus() {
        guard self.currentTaskIndex >= 0 && self.currentTaskIndex < self.scheduledTasks.count else {
            logger.warning("Attempted to update completion status, but currentTaskIndex (\(self.currentTaskIndex)) is invalid.")
            return
        }

        let task = self.scheduledTasks[self.currentTaskIndex].task
        let taskNameToLog = task.taskName ?? "Unnamed"
        let completionTime = Date() // Capture the completion time

        logger.debug("Updating completion status for task: \(taskNameToLog, privacy: .public)")
        task.lastCompleted = completionTime // Set the last completed date

        // --- Calculate nextDueDate based on repetitionInterval ---
        let repetitionIntervalSeconds = TimeInterval(task.repetitionInterval) // Convert Int32 to TimeInterval
        let secondsInDay: TimeInterval = 86400

        if repetitionIntervalSeconds > 0 {
            logger.debug("Task '\(taskNameToLog, privacy: .public)' has repetition interval: \(repetitionIntervalSeconds) seconds.")
            // Check if the interval represents whole days (>= 1 day)
            if repetitionIntervalSeconds.truncatingRemainder(dividingBy: secondsInDay) == 0 && repetitionIntervalSeconds >= secondsInDay {
                // Interval is in whole days, weeks, or months (represented as days)
                var dateComponent = DateComponents()
                // Calculate number of days
                let days = Int(repetitionIntervalSeconds / secondsInDay)
                dateComponent.day = days

                // Calculate the initial next due date
                if let calculatedDueDate = Calendar.current.date(byAdding: dateComponent, to: completionTime) {
                    // Round down to the beginning of the day (midnight)
                    task.nextDueDate = Calendar.current.startOfDay(for: calculatedDueDate)
                    logger.info("Calculated next due date (rounded down): \(task.nextDueDate!, privacy: .public) for task '\(taskNameToLog, privacy: .public)'")
                } else {
                    // Handle potential calculation error (should be rare)
                    task.nextDueDate = completionTime.addingTimeInterval(repetitionIntervalSeconds) // Fallback to simple addition
                    logger.error("Could not calculate next due date using DateComponents for task '\(taskNameToLog, privacy: .public)'. Using simple interval addition as fallback.")
                }
            } else {
                // Interval is less than a day (presumably hours or seconds) - NO rounding
                task.nextDueDate = completionTime.addingTimeInterval(repetitionIntervalSeconds)
                 logger.info("Calculated next due date (no rounding): \(task.nextDueDate!, privacy: .public) for task '\(taskNameToLog, privacy: .public)'")
            }
        } else {
            // Repetition interval is 0 (daily at midnight?) or negative (no repeat)
            // Set nextDueDate to nil as per user request (no rounding needed)
            // Or handle the '0' case specifically if it needs to be midnight *tomorrow*
            // For now, setting to nil for <= 0 intervals.
            task.nextDueDate = nil
            logger.info("Task '\(taskNameToLog, privacy: .public)' has non-positive repetition interval (\(repetitionIntervalSeconds)). Setting nextDueDate to nil.")
        }
        // --- End of nextDueDate calculation ---


        // REMOVED Save from here
        // do {
        //     if self.context.hasChanges {
        //         try self.context.save()
        //         logger.info("Successfully saved completion status and nextDueDate for task ...")
        //     } else {
        //          logger.warning("Attempted to save completion status, but no changes detected...")
        //     }
        // } catch {
        //     logger.error("Failed to save task completion status: \(error.localizedDescription)")
        // }
    }

    /// Resets the timer for the *current* task, optionally adjusting the schedule offset.
    func resetTimer() {
        guard self.currentTaskIndex != -1 && !self.isRoutineComplete else {
            logger.warning("Reset timer called but no task is active or routine is finished.")
            return
        }

        let task = self.scheduledTasks[self.currentTaskIndex].task // task is non-optional here
        let taskName = task.taskName ?? "Unnamed Task"
        // let taskName = self.scheduledTasks[self.currentTaskIndex].task?.taskName ?? "Unnamed Task"
        logger.info("Resetting timer for task '\(taskName, privacy: .public)'.")

        // Stop any existing timer
        timer?.cancel()
        timer = nil
        isRunning = false
        startTime = nil
        remainingTimeOnPause = nil
        backgroundEnterTime = nil
        isOverrun = false
        lastOffsetUpdateTime = nil
         DispatchQueue.main.async { // Ensure UI updates are on main thread
            self.isOverrun = false
            self.isRunning = false
         }


        // Re-configure the task state (resets duration, time display)
        self.configureTask(at: self.currentTaskIndex)

        self.updateScheduleOffsetString()
        self.updateEstimatedFinishingTimeString()
        logger.debug("Timer reset complete for '\(taskName, privacy: .public)'. Current schedule offset remains \(self.scheduleOffset, format: .fixed(precision: 1))s.")

        // Should it auto-start after reset? For now, no. User must press start again.
    }


    // MARK: - Timer Control

    /// Starts or resumes the timer for the current task.
    func startTimer() {
        guard self.currentTaskIndex != -1 && !self.isRoutineComplete else {
            logger.warning("Start timer called but no task active or routine complete.")
            return
        }
        guard !isRunning else {
            logger.warning("Start timer called but timer is already running.")
            return
        }

        let task = self.scheduledTasks[self.currentTaskIndex].task // task is non-optional here
        let taskName = task.taskName ?? "Unnamed Task"
        // let taskName = self.scheduledTasks[self.currentTaskIndex].task?.taskName ?? "Unnamed Task"

        // Determine the time to count down from
        if let pausedTime = self.remainingTimeOnPause {
            self.timeToCountDownAtStart = pausedTime
            logger.info("Resuming timer for task '\(taskName, privacy: .public)' with \(pausedTime, format: .fixed(precision: 1))s remaining.")
            self.remainingTimeOnPause = nil // Clear pause state
        } else {
             self.timeToCountDownAtStart = self.currentTaskDuration
            logger.info("Starting timer for task '\(taskName, privacy: .public)' for \(self.currentTaskDuration, format: .fixed(precision: 1))s.")
        }

        self.startTime = Date() // Record the exact start/resume time
        self.lastOffsetUpdateTime = self.startTime // Initialize for overrun calculation

        isRunning = true
         DispatchQueue.main.async { // Ensure UI updates are on main thread
             self.isRunning = true
         }


        // Setup the Combine timer to fire every second
        timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect().sink { [weak self] fireDate in
            guard let self = self, self.isRunning else { return } // Ensure we're still running

            let elapsedTime = fireDate.timeIntervalSince(self.startTime ?? fireDate)
            let timeRemaining = self.timeToCountDownAtStart - elapsedTime

            // Update the display regardless of overrun state first
            self.updateRemainingTimeDisplay(timeRemaining) // This now handles 00:00 correctly

            // --- Overrun Handling ---
            // Change condition to < 0 to trigger overrun only for negative time
            if timeRemaining < 0 {
                if !self.isOverrun {
                    // Set overrun flag only when time is strictly negative
                    self.isOverrun = true
                    DispatchQueue.main.async { self.isOverrun = true }
                    // self.remainingTimeString = "00:00" // No longer needed, updateRemainingTimeDisplay handles it
                    // Initialize lastOffsetUpdateTime only when overrun *starts*
                    // Use the exact time the timer was supposed to end
                    self.lastOffsetUpdateTime = self.startTime?.addingTimeInterval(self.timeToCountDownAtStart) ?? fireDate

                    let task = self.scheduledTasks[self.currentTaskIndex].task // task is non-optional here
                    let taskNameToLog = task.taskName ?? "Unnamed"
                    self.logger.warning("Task '\(taskNameToLog, privacy: .public)' timer passed 0. Entering overrun state (time: \(timeRemaining, format: .fixed(precision: 2))s).")
                    // Consider playing a subtle sound here if desired
                    // AudioServicesPlaySystemSound(1005)
                }

                // Calculate overrun time and update schedule offset
                // Ensure lastOffsetUpdateTime is not nil before calculating interval
                if let lastUpdate = self.lastOffsetUpdateTime {
                    let timeSinceLastUpdate = fireDate.timeIntervalSince(lastUpdate)
                    // Update offset continuously during overrun
                    // Note: timeSinceLastUpdate might be slightly more or less than 1.0s
                    self.scheduleOffset += timeSinceLastUpdate // Add the *actual* elapsed time during overrun
                    self.updateScheduleOffsetString()
                    self.updateEstimatedFinishingTimeString()
                    self.lastOffsetUpdateTime = fireDate // Update for the next calculation
                    self.logger.trace("Overrun: Added \(timeSinceLastUpdate, format: .fixed(precision: 1))s to offset. New offset: \(self.scheduleOffset, format: .fixed(precision: 1))s.")
                } else {
                    // Log if lastOffsetUpdateTime was unexpectedly nil during overrun
                    self.logger.error("lastOffsetUpdateTime was nil during overrun calculation.")
                    self.lastOffsetUpdateTime = fireDate // Attempt to recover
                }

            } else {
                // --- Normal Countdown or Exactly Zero ---
                // Ensure isOverrun is false if we are not strictly negative
                if self.isOverrun {
                     self.isOverrun = false
                     DispatchQueue.main.async { self.isOverrun = false }
                     self.logger.info("Exited overrun state (time: \(timeRemaining, format: .fixed(precision: 2))s).")
                     self.lastOffsetUpdateTime = nil // Reset when exiting overrun
                 }
                // self.updateRemainingTimeDisplay(timeRemaining) // Already handled above
            }
        }
    }

    /// Pauses the timer for the current task.
    func pauseTimer(isBackgrounding: Bool = false) {
        guard isRunning else {
            logger.debug("Pause timer called, but timer is not running.")
            return
        }
        logger.info("Pausing timer. \(isBackgrounding ? "(Due to backgrounding)" : "")")

        timer?.cancel() // Stop the timer publisher
        timer = nil

        // Calculate remaining time accurately based on when it started/resumed
        let elapsed = Date().timeIntervalSince(startTime ?? Date()) // Time since last start/resume
        let remaining = timeToCountDownAtStart - elapsed // Calculate actual time left

        if remaining > 0 && !isOverrun {
            // Only store remaining time if > 0 and not already in overrun
            remainingTimeOnPause = remaining
            logger.debug("Remaining time on pause stored: \(remaining, format: .fixed(precision: 1))s")
        } else {
            // If remaining is zero or negative, or we were already in overrun, clear the pause time
            remainingTimeOnPause = nil
            // Don't reset isOverrun here, as we might be pausing *during* overrun
            logger.debug("Timer paused with no positive time remaining or during overrun. Cleared remainingTimeOnPause.")
        }

        // Update published state on main thread
        DispatchQueue.main.async {
            self.isRunning = false
        }
        startTime = nil // Clear start time as it's no longer relevant for pause calculation

        // DO NOT update backgroundEnterTime here; it's handled by observeScenePhase
    }


    // MARK: - Background Handling (Implementation needed if required)
    // ...

    // MARK: - Display Formatting

    /// Updates the `remainingTimeString` published property based on the given time interval.
    /// Handles negative times correctly for overrun display.
    private func updateRemainingTimeDisplay(_ time: TimeInterval) {
        DispatchQueue.main.async { // Ensure UI updates happen on the main thread
            // Check if time is strictly less than 0 for the negative sign
            let isNegative = time < 0
            // Use floor for absolute time calculation to handle the transition at 0 correctly
            // For example, -0.5 seconds should display as 00:00, not -00:00
            let absoluteTime = floor(abs(time))
            let minutes = Int(absoluteTime) / 60
            let seconds = Int(absoluteTime) % 60

            // Format the string
            let timeString = String(format: "%02d:%02d", minutes, seconds)

            // Prepend "-" only if the original time was actually negative
            self.remainingTimeString = isNegative ? "-\(timeString)" : timeString

            // Debugging log
            self.logger.trace("Updated remaining time display: \(self.remainingTimeString, privacy: .public) for raw time \(time, format: .fixed(precision: 2))")
        }
    }


    /// Updates the `scheduleOffsetString` published property based on the `scheduleOffset`.
    private func updateScheduleOffsetString() {
        let offset = self.scheduleOffset
        var newString: String

        if abs(offset) < 1.0 {
            newString = "On schedule"
        } else {
            let minutes = Int(abs(offset)) / 60
            let seconds = Int(abs(offset)) % 60
            let formattedOffset = String(format: "%d:%02d", minutes, seconds)
            if offset < 0 {
                newString = "\(formattedOffset) ahead of schedule"
            } else {
                newString = "\(formattedOffset) behind schedule"
            }
        }
         DispatchQueue.main.async {
             self.scheduleOffsetString = newString
         }
    }
    
    /// Updates the `estimatedFinishingTimeString` published property based on the original finishing time and schedule offset.
    private func updateEstimatedFinishingTimeString() {
        let estimatedFinishingTime = originalFinishingTime.addingTimeInterval(scheduleOffset)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: estimatedFinishingTime)
        
        DispatchQueue.main.async {
            self.estimatedFinishingTimeString = "Est. finish: \(timeString)"
        }
    }

    // MARK: - Public Control Methods
    
    /// Reorders tasks in the current schedule (affects only this run, not the saved routine)
    /// - Parameters:
    ///   - source: The indices of the tasks to move
    ///   - destination: The new position for the tasks
    public func reorderTasks(from source: IndexSet, to destination: Int) {
        logger.info("Reordering tasks in running routine from \(source) to \(destination)")
        
        // Ensure we can only reorder future tasks (not completed or current)
        guard currentTaskIndex >= 0 else {
            logger.warning("Cannot reorder tasks: routine not started")
            return
        }
        
        // Adjust indices to account for completed/current tasks
        let adjustedSource = IndexSet(source.map { $0 })
        let adjustedDestination = destination
        
        // Prevent reordering completed or currently running task
        if let minIndex = adjustedSource.min(), minIndex <= currentTaskIndex {
            logger.warning("Cannot reorder completed or currently running tasks")
            return
        }
        
        if adjustedDestination <= currentTaskIndex {
            logger.warning("Cannot move tasks before the current task")
            return
        }
        
        // Perform the reorder
        scheduledTasks.move(fromOffsets: adjustedSource, toOffset: adjustedDestination)
        
        // Update next task name if it changed
        let nextIndex = currentTaskIndex + 1
        if nextIndex < scheduledTasks.count {
            self.nextTaskName = scheduledTasks[nextIndex].task.taskName
            logger.debug("Updated next task name after reorder: \(self.nextTaskName ?? "None")")
        }
        
        // Notify SwiftUI of the change
        objectWillChange.send()
        
        logger.info("Task reorder completed. New order affects only this run.")
    }
    
    /// Stops the routine and cleans up all timers and state.
    func stopRoutine() {
        logger.info("Stopping routine '\(self.routine.name ?? "Unnamed")' by user request.")
        
        // Stop and clean up timer
        timer?.cancel()
        timer = nil
        isRunning = false
        startTime = nil
        remainingTimeOnPause = nil
        backgroundEnterTime = nil
        isOverrun = false
        lastOffsetUpdateTime = nil
        
        // Update UI state on main thread
        DispatchQueue.main.async {
            self.isRunning = false
            self.objectWillChange.send()
        }
        
        logger.info("Routine stopped and all timers cleaned up.")
    }

     // MARK: - Deinitialization
     deinit {
         logger.info("RoutineRunner deinitialized.")
         timer?.cancel()
     }

    // MARK: - Scene Phase Handling

    /// Observes changes in the application's scene phase to manage the timer accordingly.
    /// Pauses the timer when the app goes to the background or becomes inactive, and handles
    /// resuming or calculating elapsed time when returning to the foreground.
    /// - Parameter newPhase: The new scene phase reported by the system (e.g., .active, .inactive, .background).
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
            // Check if we have a background entry time recorded (only set when actually going to background)
            if let backgroundEnterTime = backgroundEnterTime {
                // Calculate time spent in background
                let timeInBackground = Date().timeIntervalSince(backgroundEnterTime)
                logger.info("App was in background for \(timeInBackground, format: .fixed(precision: 1)) seconds.")
                self.backgroundEnterTime = nil // Clear the background entry time

                // If the timer was running when backgrounded
                if remainingTimeOnPause != nil {
                    // Adjust remaining time based on time spent in background
                    let newRemainingTime = (remainingTimeOnPause ?? currentTaskDuration) - timeInBackground
                    logger.debug("Adjusted remaining time on pause from \(self.remainingTimeOnPause ?? -1, format: .fixed(precision: 1))s to \(newRemainingTime, format: .fixed(precision: 1))s")

                    if newRemainingTime > 0 {
                        // Time remaining, resume timer from adjusted time
                        remainingTimeOnPause = newRemainingTime
                        startTimer() // Will use remainingTimeOnPause
                        logger.info("Resuming timer after background.")
                    } else {
                        // Time ran out while in background
                        logger.info("Time expired while in background.")
                        // Mark overrun based on how much time ran out
                        isOverrun = true // Set overrun flag immediately on main thread
                        DispatchQueue.main.async { self.isOverrun = true }

                        let overrunDuration = abs(newRemainingTime)
                        logger.info("Overrun by \(overrunDuration, format: .fixed(precision: 1)) seconds.")

                        // Directly adjust schedule offset for the overrun that occurred in the background
                        scheduleOffset += overrunDuration
                        logger.debug("Schedule offset increased by overrun duration. New offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
                        updateScheduleOffsetString()
                        updateEstimatedFinishingTimeString()

                        // Update display to 00:00 immediately
                        updateRemainingTimeDisplay(0)

                        // Restart timer in overrun mode (counting up from 0)
                        startTime = Date() // Reset start time for overrun counting
                        timeToCountDownAtStart = 0 // We are counting up now
                        remainingTimeOnPause = nil // Clear pause state
                        lastOffsetUpdateTime = Date() // Set last offset update time
                        startTimerMechanism() // Start the actual timer
                        DispatchQueue.main.async { self.isRunning = true } // Ensure UI updates
                        logger.info("Restarted timer in overrun mode after background.")
                    }
                } else {
                    // Timer wasn't running when backgrounded (e.g., paused manually before backgrounding)
                    // No need to start the timer automatically, just update display if needed.
                    logger.info("App became active, but timer was not running when backgrounded. Maintaining paused state.")
                    // Ensure display is correct if it was paused
                    if let pauseTime = remainingTimeOnPause {
                         updateRemainingTimeDisplay(pauseTime)
                    } else if !isRunning && startTime == nil && currentTaskIndex != -1 {
                         // If first task and never started, show full duration
                         updateRemainingTimeDisplay(currentTaskDuration)
                    }
                }
            } else {
                 // App became active, but wasn't backgrounded (e.g., first launch, or returning from inactive without background)
                 logger.info("App became active, no background time detected.")
                 // If we were inactive (e.g., Control Centre) but never backgrounded, ensure timer is still running if it should be
                 if !isRoutineComplete && currentTaskIndex != -1 && !isRunning && remainingTimeOnPause == nil {
                     // Timer should be running but isn't - restart it
                     logger.info("Restarting timer after inactive period without backgrounding.")
                     startTimer()
                 }
            }

        case .inactive:
            // App is transitioning away from active state (e.g., multitasking switcher, alert, Control Centre)
            logger.info("App became inactive. Not pausing timer - waiting to see if it goes to background.")
            // Don't pause immediately on inactive - this happens for Control Centre, notifications, etc.
            // Only pause if we actually go to background. This prevents interruption from
            // Control Centre access or notification panel pulls.

        case .background:
            // App entered background
            logger.info("App entered background. Pausing timer and recording entry time.")
            if isRunning {
                // Record the time we entered the background
                backgroundEnterTime = Date()
                logger.debug("Recorded background enter time: \(self.backgroundEnterTime!)")
                // Pause the timer, indicating it's due to backgrounding
                pauseTimer(isBackgrounding: true)
            } else {
                 // If timer wasn't running (already paused), still record background time
                 // in case it gets terminated. Handle this on foregrounding.
                 backgroundEnterTime = Date()
                 logger.debug("App entered background while timer was paused. Recorded background enter time: \(self.backgroundEnterTime!)")
            }

        @unknown default:
            // Handle future scene phases
            logger.warning("Unknown scene phase encountered: \(String(describing: newPhase)). No action taken.")
            break
        }
    }

    // MARK: - Timer Control

    /// Internal function to create and start the Combine timer subscription.
    private func startTimerMechanism() {
        // Implementation of startTimerMechanism
    }

    // MARK: - Progress Calculation
    /// Updates the `completedDuration` based on the `currentTaskIndex`.
    private func updateCompletedDuration() {
        // Capture the index *before* going async to prevent race condition on completion
        let indexAtScheduling = self.currentTaskIndex

        // Use weak self in async block to avoid potential retain cycles
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Use the captured index for the check
            guard indexAtScheduling >= 0 else {
                // If no task was active when scheduled (index was -1), ensure completed duration is 0
                if self.completedDuration != 0 {
                    self.completedDuration = 0
                    self.logger.debug("Updated completed duration: 0s (No active task / Index was \(indexAtScheduling))")
                    self.objectWillChange.send()
                }
                return
            }

            // Optional: Add an extra safety check in case scheduledTasks changed size unexpectedly
            guard indexAtScheduling < self.scheduledTasks.count else {
                 self.logger.warning("updateCompletedDuration async block ran, but captured index \(indexAtScheduling) is out of bounds for current task count \(self.scheduledTasks.count). Bailing out.")
                 return
            }

            // Sum the allocated durations of all tasks *before* the captured index
            let duration = self.scheduledTasks.prefix(indexAtScheduling).reduce(0) { $0 + $1.allocatedDuration }
            if self.completedDuration != duration {
                self.completedDuration = duration
                self.logger.debug("Updated completed duration: \(duration / 60, format: .fixed(precision: 1))m (using captured index \(indexAtScheduling))")
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Public Control Methods

    /// Delays the current task by moving it later in the execution queue.
    /// Does not affect the saved routine order.
    /// - Parameter delayCount: The number of tasks to move the current task after. Defaults to 3.
    public func delayCurrentTask(by delayCount: Int = 3) {
        logger.debug("Attempting to delay task at index \(self.currentTaskIndex) by \(delayCount) positions.")

        // Ensure index is valid and there are tasks remaining after the current one
        // Use the computed property here for consistency
        guard canDelayCurrentTask else {
            logger.warning("Cannot delay task: Current state does not allow delay (index: \(self.currentTaskIndex), schedule count: \(self.scheduledTasks.count))")
            // Optionally provide user feedback here if needed
            return
        }

        // Ensure delayCount is positive
        guard delayCount > 0 else {
            logger.warning("Cannot delay task: delayCount must be positive (was \(delayCount)).")
            return
        }

        // Stop the current timer logic (like pausing) but don't change isRunning state yet
        timer?.cancel()
        timer = nil
        if let start = startTime {
            // Capture remaining time if timer was running, although it won't be used for the delayed task later
            let elapsed = Date().timeIntervalSince(start)
            let timeRemaining = max(0, timeToCountDownAtStart - elapsed) // Use the effective start duration
             logger.debug("Timer stopped for delay. \(timeRemaining, format: .fixed(precision: 1))s were remaining.")
        }
        startTime = nil
        remainingTimeOnPause = nil // Reset pause state
        backgroundEnterTime = nil
        isOverrun = false // Reset overrun state for the *next* task
        lastOffsetUpdateTime = nil

        // --- Reorder the scheduledTasks array ---
        let taskToDelay = scheduledTasks.remove(at: currentTaskIndex)
        logger.info("Removed task '\(taskToDelay.task.taskName ?? "Unnamed")' from index \(self.currentTaskIndex) for delay.")

        // Calculate the new index, ensuring it doesn't exceed bounds
        // The index in the *modified* array where the task should be inserted is `currentTaskIndex + delayCount`.
        // We clamp this to the end of the *modified* array.
        let insertionIndex = min(currentTaskIndex + delayCount, scheduledTasks.count)
        scheduledTasks.insert(taskToDelay, at: insertionIndex)
        logger.info("Inserted task '\(taskToDelay.task.taskName ?? "Unnamed")' back at index \(insertionIndex). New count: \(self.scheduledTasks.count)")

        // --- Configure the *new* task at currentTaskIndex ---
        // The currentTaskIndex itself doesn't change yet, but the task *at* that index has changed.
        // We need to configure and start the timer for this new task.
        logger.info("Re-configuring runner for the new task at index \(self.currentTaskIndex).")
        // We manually set isRunning false before configureTask, then true after startTimer
        // to ensure the UI updates correctly if it was paused.
        let wasRunning = self.isRunning // Store original state
        self.isRunning = false // Temporarily set to false for configureTask reset
        configureTask(at: currentTaskIndex) // This prepares the *new* task at the current index

        // Start the timer for the *new* current task only if the routine was running before delay
        if wasRunning {
            logger.debug("Routine was running before delay, starting timer for the new task.")
            startTimer()
        } else {
             logger.debug("Routine was paused before delay, leaving timer paused for the new task.")
             // No need to explicitly set isRunning = false, configureTask did that.
             // We might need to update the display string if configureTask doesn't handle paused state display correctly.
             // ConfigureTask calls updateRemainingTimeDisplay, which should be sufficient.
        }

        // Log the new order for debugging (optional)
        let newOrderNames = scheduledTasks.map { $0.task.taskName ?? "Unnamed" }
        logger.debug("New task order after delay: \(newOrderNames.joined(separator: ", "))")

        // Notify SwiftUI that the underlying data driving the list has changed
        objectWillChange.send()
    }

    // MARK: - Background Handling

    /// Handles the app entering the background.
    func handleAppDidEnterBackground() {
        logger.info("App did enter background.")
        // Record the time we entered background
        backgroundEnterTime = Date()
        // Pause the timer if it's running
        if isRunning {
            logger.debug("Pausing timer due to backgrounding.")
            // Pass true to indicate it's a background pause
            // This prevents storing remainingTimeOnPause incorrectly if already overrun
            pauseTimer(isBackgrounding: true)
        }
    }

    /// Handles the app entering the foreground.
    func handleAppWillEnterForeground() {
        logger.info("App will enter foreground.")
        guard let bgEnterTime = backgroundEnterTime else {
            logger.debug("App entering foreground, but no background enter time recorded. No timer adjustments needed.")
            return // Wasn't backgrounded or state lost
        }

        let timeInBackground = Date().timeIntervalSince(bgEnterTime)
        logger.debug("Time spent in background: \(timeInBackground, format: .fixed(precision: 1)) seconds.")
        self.backgroundEnterTime = nil // Reset background time

        // If the timer was running *before* backgrounding (indicated by having stored remainingTimeOnPause
        // or if it was in overrun state), we might need to resume or adjust.
        // The pauseTimer(isBackgrounding: true) logic should have correctly managed the state.
        // If remainingTimeOnPause was set, startTimer() will resume correctly.
        // If it was overrun, startTimer() might need adjustment or just continue overrun logic.
        
        // Check if we *should* be running based on state before backgrounding.
        // The easiest way is to check if remainingTimeOnPause was captured by pauseTimer,
        // or if the routine is not complete and wasn't paused manually before backgrounding.
        // Let's just try to restart if the routine isn't complete and wasn't manually paused.
        // We rely on `startTimer` to correctly use `remainingTimeOnPause` if it exists.

        if !isRoutineComplete && currentTaskIndex != -1 {
            // Check if the timer was *supposed* to be running before backgrounding.
            // We know it was paused by handleAppDidEnterBackground if it was running.
            // If remainingTimeOnPause is nil, it means either the timer wasn't running before,
            // or it ran out / was in overrun while paused.
            // If remainingTimeOnPause has a value, it means the timer was running and had time left.
            
            if remainingTimeOnPause != nil {
                 logger.info("Resuming timer after returning from background.")
                 startTimer() // This will use remainingTimeOnPause correctly
            } else {
                // Timer was paused manually before background, was in overrun, or completed in background.
                // No need to automatically restart it. The state should be correct.
                logger.info("Timer was not running or had no time left before backgrounding. Not resuming automatically.")
            }
        } else {
            logger.debug("Routine is complete or no task active. Not resuming timer.")
        }
    }

    // MARK: - Core Data Saving

    /// Records the completion time for a task using a circular buffer approach (max 100 entries)
    private func recordCompletionTime(for task: CDTask, duration: TimeInterval) {
        logger.info("Recording completion time of \(duration, format: .fixed(precision: 1))s for task '\(task.taskName ?? "Unnamed")'")
        
        // Get existing completion times
        let existingTimes = (task.completionTimes as? Set<CDTaskCompletionTime>) ?? []
        logger.debug("Existing completion times count: \(existingTimes.count)")
        
        if existingTimes.count < 100 {
            // Haven't reached the limit yet, just add a new entry
            let newCompletionTime = CDTaskCompletionTime(context: context)
            newCompletionTime.completionTime = duration
            newCompletionTime.date = Date()
            newCompletionTime.index = Int16(existingTimes.count)
            newCompletionTime.task = task
            
            task.addToCompletionTimes(newCompletionTime)
            logger.debug("Added completion time at index \(existingTimes.count)")
            
            // Log the average after adding
            if let avgTime = task.averageCompletionTime {
                logger.debug("New average completion time: \(avgTime, format: .fixed(precision: 1))s")
            } else {
                logger.warning("Average completion time is nil after adding new entry")
            }
        } else {
            // We have 100 entries, need to find the oldest one to replace
            // Find the next index to overwrite (circular buffer)
            let sortedTimes = existingTimes.sorted { $0.index < $1.index }
            
            // Calculate next index in circular buffer
            let maxIndex = sortedTimes.last?.index ?? 99
            let nextIndex = (maxIndex + 1) % 100
            
            // Find the entry with the target index
            if let timeToUpdate = sortedTimes.first(where: { $0.index == nextIndex }) {
                // Update existing entry
                timeToUpdate.completionTime = duration
                timeToUpdate.date = Date()
                logger.debug("Updated completion time at index \(nextIndex) (circular buffer)")
            } else {
                // This shouldn't happen, but handle it gracefully
                logger.warning("Could not find completion time entry at index \(nextIndex), creating new one")
                let newCompletionTime = CDTaskCompletionTime(context: context)
                newCompletionTime.completionTime = duration
                newCompletionTime.date = Date()
                newCompletionTime.index = Int16(nextIndex)
                newCompletionTime.task = task
                
                task.addToCompletionTimes(newCompletionTime)
            }
        }
    }
    
    /// Saves the managed object context if there are changes, performing the save on the context's queue.
    private func saveContext() {
        // Use perform to ensure saving happens on the context's queue (likely main queue for viewContext)
        context.perform {
            guard self.context.hasChanges else {
                self.logger.debug("Save context called, but no changes detected.")
                return
            }

            do {
                try self.context.save()
                self.logger.info("Managed object context saved successfully.")
                
                // Verify completion times were saved
                for task in self.scheduledTasks.map({ $0.task }) {
                    if task.shouldTrackAverageTime {
                        let count = (task.completionTimes as? Set<CDTaskCompletionTime>)?.count ?? 0
                        self.logger.debug("Task '\(task.taskName ?? "Unnamed")' has \(count) completion times saved")
                        if let avgTime = task.averageCompletionTime {
                            self.logger.debug("Average completion time: \(avgTime, format: .fixed(precision: 1))s")
                        }
                    }
                }
            } catch {
                // Log the detailed error
                let nserror = error as NSError
                self.logger.critical("Unresolved error saving context: \(nserror), \(nserror.userInfo)")
                // Consider more robust error handling depending on the app's needs
                // fatalError("Unresolved error \(nserror), \(nserror.userInfo)") // Avoid fatalError in production
            }
        }
    }
}

// Extension for TimeInterval formatting (optional, can be placed elsewhere)
extension TimeInterval {
    func format(using units: NSCalendar.Unit = [.minute, .second]) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: self) ?? "00:00"
    }
}
