    import Foundation
    import SwiftUI // Needed for @Published
    import Combine // Needed for Timer
    import OSLog // Needed for logging
    import CoreData // Import CoreData

    /// Manages the state and logic for running a routine, including the timer.
    class RoutineRunnerViewModel: ObservableObject {

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

        // MARK: - Core Data & Routine Properties

        /// The Core Data managed object context.
        private let context: NSManagedObjectContext
        /// The list of tasks (NSManagedObject subclass) in the current routine.
        /// We'll fetch these later. For now, create samples.
        private var tasks: [Task] = []
        /// The index of the currently active task in the `tasks` array. -1 if not started or complete.
        private var currentTaskIndex: Int = -1

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
        /// Tracks if the timer for the current task has hit 00:00 and is now counting late time.
        public var isOverrun: Bool = false
        /// Timestamp of the last time the schedule offset was updated due to overrun.
        private var lastOffsetUpdateTime: Date? = nil


        // MARK: - Schedule Offset Properties

        /// Tracks the total deviation from the scheduled completion times (in seconds).
        /// Negative means ahead of schedule, Positive means behind schedule.
        private var scheduleOffset: TimeInterval = 0

        // MARK: - Logging

        /// Logger for detailed debug and informational messages within the view model.
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineRunnerViewModel")
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

        /// Initializes the ViewModel with the managed object context.
        /// - Parameter context: The NSManagedObjectContext for Core Data operations.
        init(context: NSManagedObjectContext) {
            self.context = context
            logger.info("\(self.logTime()): RoutineRunnerViewModel initialized with context.")
            createSampleTasksIfNeeded() // Create sample tasks in Core Data if none exist
            fetchTasks() // Fetch tasks from Core Data
            prepareFirstTask() // Set up the first task (if any)
            updateScheduleOffsetString() // Initialize offset string
        }

        /// Creates sample Task entities in Core Data if the store is empty.
        private func createSampleTasksIfNeeded() {
            logger.debug("\(self.logTime()): Checking if sample tasks need to be created...")
            let fetchRequest: NSFetchRequest<Task> = Task.fetchRequest()

            do {
                let existingTasks = try context.fetch(fetchRequest)
                if existingTasks.isEmpty {
                    logger.info("\(self.logTime()): No existing tasks found. Creating sample tasks in Core Data.")
                    // Define sample data
                    let sampleData: [(name: String, duration: Double)] = [
                        ("Task 1: Warm-up", 10.0),
                        ("Task 2: Main Exercise", 45.0),
                        ("Task 3: Quick Break", 15.0),
                        ("Task 4: Another Exercise", 30.0),
                        ("Task 5: Cool Down", 25.0)
                    ]

                    // Create and save Task managed objects
                    for data in sampleData {
                        let newTask = Task(context: context) // Create using the context
                        newTask.name = data.name
                        newTask.duration = data.duration // Assign duration (Double)
                        // Add other attributes like creation date or order if needed later
                    }

                    // Save the context
                    if context.hasChanges {
                        try context.save()
                        logger.info("\(self.logTime()): Successfully saved \(sampleData.count) sample tasks to Core Data.")
                    }
                } else {
                    logger.info("\(self.logTime()): \(existingTasks.count) tasks already exist in Core Data. No sample tasks created.")
                }
            } catch {
                logger.error("\(self.logTime()): Failed to check for or create sample tasks: \(error.localizedDescription)")
                // Handle the error appropriately in a real app (e.g., show an alert)
            }
        }

        /// Fetches the tasks from Core Data, sorted by name.
        /// Replace sorting by name with a dedicated order attribute later for robustness.
        private func fetchTasks() {
            logger.debug("\(self.logTime()): Fetching tasks from Core Data...")
            let fetchRequest: NSFetchRequest<Task> = Task.fetchRequest()

            // Sort by name for predictable order (Task 1, Task 2, etc.)
            let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)
            fetchRequest.sortDescriptors = [sortDescriptor]

            do {
                tasks = try context.fetch(fetchRequest)
                logger.info("\(self.logTime()): Successfully fetched and sorted \(self.tasks.count) tasks by name.")
                currentTaskIndex = -1 // Reset index after fetching
                isRoutineComplete = tasks.isEmpty // Mark complete if no tasks fetched
            } catch {
                logger.error("\(self.logTime()): Failed to fetch tasks: \(error.localizedDescription)")
                tasks = [] // Ensure tasks array is empty on failure
                isRoutineComplete = true
                currentTaskName = "Error Loading Tasks"
            }
        }


        /// Sets up the very first task without starting the timer.
        private func prepareFirstTask() {
            guard !tasks.isEmpty else {
                logger.warning("\(self.logTime()): Prepare first task called, but no tasks loaded or fetched.")
                if currentTaskName == "Loading..." { // Avoid overwriting error message
                    currentTaskName = "No Tasks Available"
                }
                isRoutineComplete = true
                return
            }
            // If not already errored or completed
            if currentTaskIndex == -1 && !isRoutineComplete {
                currentTaskIndex = 0
                logger.info("\(self.logTime()): Preparing first task.")
                configureTask(at: currentTaskIndex)
            }
        }

        // MARK: - Task Management

        /// Configures the view model state for the task at the given index. Does not start the timer.
        /// - Parameter index: The index of the task in the `tasks` array.
        private func configureTask(at index: Int) {
            guard index >= 0 && index < tasks.count else {
                logger.error("\(self.logTime()): Configure task called with invalid index: \(index). Tasks count: \(self.tasks.count)")
                completeRoutine() // Mark routine complete if index is invalid
                return
            }

            let task = tasks[index] // task is now a Task NSManagedObject

            // Access properties using Core Data generated accessors
            // Use default values if name is nil (shouldn't happen if set correctly)
            currentTaskName = task.name ?? "Unnamed Task"
            currentTaskDuration = task.duration // duration is Double, compatible with TimeInterval
            logger.info("\(self.logTime()): Configuring task \(index + 1)/\(self.tasks.count): '\(self.currentTaskName)' duration: \(self.currentTaskDuration)s")

            // Reset timer state variables for the new task
            timer?.cancel()
            timer = nil
            isRunning = false
            startTime = nil
            remainingTimeOnPause = nil
            backgroundEnterTime = nil
            isOverrun = false
            lastOffsetUpdateTime = nil

            updateRemainingTimeDisplay(currentTaskDuration) // Show full duration initially
            updateScheduleOffsetString() // Update offset string display
        }

        /// Advances to the next task in the routine.
        private func advanceToNextTask() {
            logger.debug("\(self.logTime()): Attempting to advance to the next task from index \(self.currentTaskIndex).")
            guard currentTaskIndex >= 0 else {
                logger.warning("\(self.logTime()): Cannot advance task, current index is invalid (\(self.currentTaskIndex)).")
                if !tasks.isEmpty { prepareFirstTask() } // Try to recover by preparing first task
                return
            }

            let nextIndex = currentTaskIndex + 1
            if nextIndex < tasks.count {
                logger.info("\(self.logTime()): Advancing to task \(nextIndex + 1).")
                currentTaskIndex = nextIndex
                configureTask(at: currentTaskIndex)
                // Auto-start the next timer
                startTimer()
            } else {
                logger.info("\(self.logTime()): Advanced past the last task. Routine complete.")
                completeRoutine()
            }
        }

        /// Marks the routine as complete and updates the UI state.
        private func completeRoutine() {
            logger.log("\(self.logTime()): Routine completed. Final schedule offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
            currentTaskIndex = -1 // Reset index
            currentTaskName = "Routine Complete!"
            remainingTimeString = "--:--" // Indicate no timer
            isRunning = false
            isRoutineComplete = true // Update published property
            timer?.cancel()
            timer = nil
            // Keep the final schedule offset string displayed
        }


        // MARK: - User Actions

        /// Called when the user taps the "Done" button. Marks the current task complete and moves to the next.
        func markTaskComplete() {
            guard currentTaskIndex != -1 && currentTaskIndex < tasks.count && !isRoutineComplete else {
                logger.warning("\(self.logTime()): Mark complete called but no task is active or routine is finished.")
                return
            }
            // Get current task name safely *before* potentially advancing index
            let completedTaskName = tasks[currentTaskIndex].name ?? "Unnamed Task"
            logger.info("\(self.logTime()): User marked task '\(completedTaskName)' complete.")

            // Stop the timer mechanism immediately
            timer?.cancel()
            timer = nil
            isRunning = false // Explicitly set isRunning false

            var remainingTimeForOffsetCalc: TimeInterval = 0

            if isOverrun {
                // Task was overrun when 'Done' was hit. Offset already penalized.
                remainingTimeForOffsetCalc = 0
                logger.debug("\(self.logTime()): Task completed during overrun. No additional offset change from remaining time.")
            } else if let startTime = startTime {
                // Timer was running normally. Calculate actual remaining time.
                let elapsedTime = Date().timeIntervalSince(startTime)
                remainingTimeForOffsetCalc = max(0, self.timeToCountDownAtStart - elapsedTime)
                logger.debug("\(self.logTime()): Task completed early/on-time while running. Elapsed: \(elapsedTime, format: .fixed(precision: 2))s. StartCountdown: \(self.timeToCountDownAtStart, format: .fixed(precision: 2))s. Remaining: \(remainingTimeForOffsetCalc, format: .fixed(precision: 2))s")
            } else if let pausedTime = remainingTimeOnPause {
                // Timer was paused. Use the saved pause time.
                remainingTimeForOffsetCalc = pausedTime
                logger.debug("\(self.logTime()): Task completed while paused. Remaining from pause: \(remainingTimeForOffsetCalc, format: .fixed(precision: 2))s")
            } else {
                // Timer wasn't running or paused (e.g., hit Done immediately). Use full duration.
                remainingTimeForOffsetCalc = currentTaskDuration
                logger.debug("\(self.logTime()): Task completed without timer active. Remaining is full duration: \(remainingTimeForOffsetCalc, format: .fixed(precision: 2))s")
            }

            // Subtract remaining time from offset
            self.scheduleOffset -= remainingTimeForOffsetCalc
            logger.info("\(self.logTime()): Schedule offset updated by -\(remainingTimeForOffsetCalc, format: .fixed(precision: 1))s. New offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
            updateScheduleOffsetString()

            // Reset timer state variables fully before advancing
            self.startTime = nil
            self.remainingTimeOnPause = nil
            self.backgroundEnterTime = nil
            self.isOverrun = false
            self.lastOffsetUpdateTime = nil
            self.timeToCountDownAtStart = 0

            advanceToNextTask()
        }


        // MARK: - Timer Control

        /// Starts or resumes the timer for the current task.
        func startTimer() {
            guard currentTaskIndex != -1 && currentTaskIndex < tasks.count && !isRoutineComplete else {
                logger.warning("\(self.logTime()): Start timer called but no task is active or routine is complete.")
                return
            }
            guard !isRunning else {
                logger.warning("\(self.logTime()): Start timer called but timer is already running.")
                return
            }

            let taskToStartName = tasks[currentTaskIndex].name ?? "Unnamed Task"
            logger.info("\(self.logTime()): Starting timer for task: \(taskToStartName)")
            isRunning = true

            // Determine countdown duration (use paused time if available, else full duration)
            timeToCountDownAtStart = remainingTimeOnPause ?? currentTaskDuration
            startTime = Date()

            // --- Conditional Reset of Overrun State ---
            // Only reset overrun flags if we are NOT resuming directly into an overrun state.
            // Detect resuming into overrun: remainingTimeOnPause was provided and <= 0.
            let isResumingIntoOverrun = (remainingTimeOnPause != nil && (remainingTimeOnPause ?? 0) <= 0)

            if !isResumingIntoOverrun {
                isOverrun = false
                lastOffsetUpdateTime = startTime // Use current time as base for offset if starting fresh/positive
                logger.debug("startTimer: Initializing fresh countdown or resuming with time > 0.")
            } else {
                // If resuming into overrun, keep the existing isOverrun flag (should be true)
                // and crucially, keep the existing lastOffsetUpdateTime (should have been set accurately by appDidEnterForeground)
                logger.debug("startTimer: Resuming directly into overrun state. Preserving isOverrun and lastOffsetUpdateTime.")
            }
            // --- End Conditional Reset ---

            remainingTimeOnPause = nil // Always clear pause state after using it
            backgroundEnterTime = nil // Always clear background state

            // Clear any existing timer
            timer?.cancel()

            // Create and start the timer publisher
            timer = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] fireDate in
                    // Using local formatter for sink as Date() is slightly different here
                    let tickLogTime = RoutineRunnerViewModel.logDateFormatter.string(from: fireDate) // Use fireDate for tick time
                    guard let self = self, let startTime = self.startTime else {
                        self?.logger.warning("\(tickLogTime): Timer fired but self or startTime was nil. Cancelling timer.")
                        self?.timer?.cancel()
                        self?.isRunning = false
                        return
                    }

                    // --- Timer Tick Logic ---
                    guard self.currentTaskIndex != -1 && self.currentTaskIndex < self.tasks.count else {
                        self.logger.error("\(tickLogTime): Timer fired but currentTaskIndex \(self.currentTaskIndex) is invalid. Stopping timer.")
                        self.timer?.cancel()
                        self.isRunning = false
                        self.completeRoutine() // Or handle error differently
                        return
                    }

                    let elapsedTime = fireDate.timeIntervalSince(startTime)
                    let actualRemainingTime = self.timeToCountDownAtStart - elapsedTime

                    if actualRemainingTime > 0 {
                        // Still counting down normally
                        if self.isOverrun {
                            self.logger.warning("\(tickLogTime): Timer tick found positive remaining time but was marked as overrun. Resetting overrun state.")
                            self.isOverrun = false // Reset overrun state if time becomes positive again (shouldn't happen)
                        }
                        self.updateRemainingTimeDisplay(actualRemainingTime)

                    } else {
                        // Time is up or has passed (overrun condition)
                        self.updateRemainingTimeDisplay(0) // Show 00:00

                        if !self.isOverrun {
                            // First tick where time is <= 0. Just mark it and record the time.
                            self.isOverrun = true
                            self.lastOffsetUpdateTime = fireDate
                            let currentTaskNameForLog = self.tasks[self.currentTaskIndex].name ?? "Unnamed Task"
                            self.logger.info("\(tickLogTime): Task '\(currentTaskNameForLog)' timer hit 00:00. Entering overrun state. Offset update starts next tick.")
                            // *** No scheduleOffset change on this first tick ***
                        } else {
                            // Already in overrun state. Increment offset based on time since last update.
                            guard let lastUpdate = self.lastOffsetUpdateTime else {
                                self.logger.error("\(tickLogTime): Overrun state encountered but lastOffsetUpdateTime is nil. Resetting state.")
                                self.lastOffsetUpdateTime = fireDate
                                // Don't add penalty here without a valid baseline
                                return
                            }

                            let timeSinceLastOffsetTick = fireDate.timeIntervalSince(lastUpdate)
                            if timeSinceLastOffsetTick >= 1.0 {
                                let secondsToIncrement = Int(floor(timeSinceLastOffsetTick))
                                if secondsToIncrement > 0 {
                                    self.scheduleOffset += Double(secondsToIncrement)
                                    // Advance lastOffsetUpdateTime by exactly the number of seconds processed
                                    self.lastOffsetUpdateTime = lastUpdate.addingTimeInterval(Double(secondsToIncrement))
                                    self.updateScheduleOffsetString()
                                    self.logger.debug("\(tickLogTime): Timer overrun: Incremented offset by \(secondsToIncrement)s. New offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
                                }
                            }
                        }
                    }
                }
            logger.debug("\(self.logTime()): Timer started successfully. Counting down from: \(self.timeToCountDownAtStart, format: .fixed(precision: 2))s")
        }

        /// Pauses the currently running timer. Handles both normal and overrun states.
        func pauseTimer() {
            guard isRunning else {
                logger.warning("\(self.logTime()): Pause timer called but timer is not running.")
                return
            }

            let taskNameToPause = (currentTaskIndex != -1 && currentTaskIndex < tasks.count) ? tasks[currentTaskIndex].name ?? "Unnamed Task" : "Invalid Task"
            logger.info("\(self.logTime()): Pausing timer for task: \(taskNameToPause)")
            let pauseTime = Date() // Use specific pause time for calculations/logs below
            let pauseLogTime = logTime() // Get formatted string once

            timer?.cancel() // Stop the timer publisher
            timer = nil
            isRunning = false

            // Calculate elapsed time since start/resume
            if let startTime = startTime {
                let elapsedTime = pauseTime.timeIntervalSince(startTime)

                if isOverrun {
                    // Paused during overrun. Offset is updated by timer ticks.
                    // Ensure the offset is updated for the *last* partial second before pause if necessary
                    let timeSinceLastOffsetTick = pauseTime.timeIntervalSince(self.lastOffsetUpdateTime ?? startTime)
                    if timeSinceLastOffsetTick >= 1.0 {
                        // This means a full second (or more) passed between the last tick and the pause. Update offset.
                        let secondsToIncrement = Int(floor(timeSinceLastOffsetTick))
                        if secondsToIncrement > 0 {
                            self.scheduleOffset += Double(secondsToIncrement)
                            self.updateScheduleOffsetString()
                            // Update lastOffsetUpdateTime to reflect this catch-up
                            self.lastOffsetUpdateTime = (self.lastOffsetUpdateTime ?? startTime).addingTimeInterval(Double(secondsToIncrement))
                            logger.debug("\(pauseLogTime): Paused during overrun: Caught up offset by \(secondsToIncrement)s just before pause. New offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
                        }
                    }

                    remainingTimeOnPause = 0 // No remaining time when overrun
                    logger.debug("\(pauseLogTime): Paused during overrun. Final offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")

                } else {
                    // Paused during normal countdown. Calculate remaining time.
                    let actualRemainingTime = self.timeToCountDownAtStart - elapsedTime
                    remainingTimeOnPause = max(0, actualRemainingTime) // Store the calculated remaining time
                    logger.debug("\(pauseLogTime): Timer paused normally. Elapsed: \(elapsedTime, format: .fixed(precision: 2))s. Remaining saved: \(self.remainingTimeOnPause ?? -1, format: .fixed(precision: 2))s")
                    self.updateRemainingTimeDisplay(remainingTimeOnPause!) // Added self.
                }

            } else {
                logger.error("\(pauseLogTime): Timer paused but startTime was nil. State inconsistent. Setting pause state defensively.")
                remainingTimeOnPause = isOverrun ? 0 : currentTaskDuration // Best guess
                updateRemainingTimeDisplay(remainingTimeOnPause ?? 0)
            }

            // Clear startTime, keep isOverrun state, keep lastOffsetUpdateTime
            startTime = nil
        }


        /// Resets the *current* task timer to its full duration and resets overrun/offset changes *for this task*.
        /// Does NOT reset the overall scheduleOffset accrued from previous tasks.
        func resetTimer() {
            guard currentTaskIndex != -1 && currentTaskIndex < tasks.count && !isRoutineComplete else {
                logger.warning("\(self.logTime()): Reset timer called but no task is active or routine is complete.")
                return
            }
            let taskToResetName = tasks[currentTaskIndex].name ?? "Unnamed Task"
            logger.info("\(self.logTime()): Resetting timer for current task: \(taskToResetName)")

            // Stop the timer mechanism
            timer?.cancel()
            timer = nil
            isRunning = false

            // Reset timer-specific state variables
            startTime = nil
            remainingTimeOnPause = nil
            backgroundEnterTime = nil
            isOverrun = false
            lastOffsetUpdateTime = nil
            timeToCountDownAtStart = 0

            // Reset display to the full duration of the *current* task
            updateRemainingTimeDisplay(currentTaskDuration)

            // Note: Overall scheduleOffset is NOT changed.
            logger.debug("\(self.logTime()): Current task timer reset. Overall schedule offset remains: \(self.scheduleOffset, format: .fixed(precision: 1))s")
        }


        // MARK: - UI Update Helpers

        /// Updates the remaining time display string (MM:SS). Clamps input time >= 0.
        private func updateRemainingTimeDisplay(_ time: TimeInterval) {
            let clampedTime = max(0, time)
            remainingTimeString = formatTimeInterval(clampedTime)
        }

        /// Updates the `scheduleOffsetString` based on the current `scheduleOffset`.
        private func updateScheduleOffsetString() {
            let absoluteOffset = abs(scheduleOffset)
            let formattedOffset = formatTimeInterval(absoluteOffset)
            let tolerance = 0.1 // Tolerance for floating point comparison

            if absoluteOffset < tolerance {
                scheduleOffsetString = "On schedule"
            } else if scheduleOffset < 0 { // Negative offset means ahead
                scheduleOffsetString = "\(formattedOffset) ahead of schedule"
            } else { // Positive offset means behind
                scheduleOffsetString = "\(formattedOffset) behind schedule"
            }
            logger.debug("\(self.logTime()): Updated schedule offset string: '\(self.scheduleOffsetString)' (Raw offset: \(self.scheduleOffset, format: .fixed(precision: 2))s)")
        }


        /// Formats a time interval (in seconds) into a MM:SS string.
        private func formatTimeInterval(_ interval: TimeInterval) -> String {
            guard interval.isFinite else {
                logger.warning("Attempted to format non-finite time interval: \(interval)")
                return "--:--"
            }
            let totalSeconds = Int(abs(interval).rounded())
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        // MARK: - App Lifecycle Handlers

        /// Called when the app is about to lose active status.
        func appWillResignActive() {
            logger.info("\(self.logTime()): App will resign active.")
            // If isRunning, could potentially call pauseTimer here, but backgrounding is more definitive.
        }

        /// Called when the app enters the background.
        func appDidEnterBackground() {
            let logTime = self.logTime() // Get time once
            logger.info("\(logTime): App did enter background.")
            if isRunning {
                backgroundEnterTime = Date()
                logger.debug("\(logTime): Timer was running. Recording background enter time: \(self.backgroundEnterTime!)")
                pauseTimer() // Pause the timer state and mechanism
                logger.debug("\(logTime): Timer paused due to entering background.")
            } else {
                logger.debug("\(logTime): App entered background, but timer was not running.")
                backgroundEnterTime = nil // Ensure cleared if not running
            }
        }

        /// Called when the app returns to the active foreground state.
        func appDidEnterForeground() {
            let logTime = self.logTime() // Get time once
            logger.info("\(logTime): App did enter foreground.")
            guard let backgroundEnterTime = backgroundEnterTime else {
                logger.debug("\(logTime): App entered foreground, but was not backgrounded while timer was running/paused. No timer adjustment needed.")
                // If it was paused *before* backgrounding, it should remain paused.
                // If it wasn't running or paused, no state change needed.
                return
            }

            // --- Was running (and thus paused by background handler) when backgrounded ---
            let timeInBackground = Date().timeIntervalSince(backgroundEnterTime)
            logger.debug("\(logTime): App returned from background. Time spent in background: \(timeInBackground, format: .fixed(precision: 2))s")

            // Clear background marker time
            self.backgroundEnterTime = nil

            // Check the state *as it was left by pauseTimer* when backgrounding occurred
            if isOverrun {
                // CASE 1: Timer was *already* in overrun when backgrounded.
                // We need to add the time spent in background to the schedule offset.
                self.scheduleOffset += timeInBackground
                logger.info("\(logTime): Resumed from background during overrun. Added \(timeInBackground, format: .fixed(precision: 1))s to offset. New offset: \(self.scheduleOffset, format: .fixed(precision: 1))s")
                updateScheduleOffsetString()
                // Display is 00:00, isOverrun is still true.
                updateRemainingTimeDisplay(0)
                // Restart the timer - it will continue incrementing the offset.
                startTimer()

            } else if let pausedTime = remainingTimeOnPause {
                // CASE 2: Timer was running normally and paused for background
                let newRemainingTime = pausedTime - timeInBackground

                if newRemainingTime > 0 {
                    // Subcase 2a: Time still remains. Resume timer normally.
                    logger.info("\(logTime): Resuming timer after background. Time left: \(newRemainingTime, format: .fixed(precision: 2))s")
                    self.remainingTimeOnPause = newRemainingTime // Set remaining time for startTimer
                    startTimer() // Resume
                } else {
                    // Subcase 2b: Time ran out completely while in the background.
                    let overrunWhileBackground = -newRemainingTime
                    logger.info("\(logTime): Timer finished while in background. Overrun by: \(overrunWhileBackground, format: .fixed(precision: 2))s")

                    // Add the overrun time to the schedule offset
                    self.scheduleOffset += overrunWhileBackground
                    updateScheduleOffsetString()

                    // Mark as overrun, update display to 00:00.
                    self.isOverrun = true
                    self.remainingTimeOnPause = 0 // Explicitly set to 0 for consistency
                    updateRemainingTimeDisplay(0)

                    // Set the lastOffsetUpdateTime to the point where overrun started *in the background*
                    // This allows the timer to correctly calculate further offset when it restarts.
                    // backgroundEnterTime + pausedTime = time when timer hit 00:00
                    self.lastOffsetUpdateTime = backgroundEnterTime.addingTimeInterval(pausedTime)

                    // Restart the timer - it will now start incrementing the offset.
                    logger.debug("\(logTime): Restarting timer in overrun state after finishing in background.")
                    startTimer()
                }
            } else {
                // Fallback for inconsistent state.
                logger.error("\(logTime): Inconsistent state: Entered foreground with backgroundEnterTime set, but remainingTimeOnPause is nil and not overrun. Resetting current task timer.")
                resetTimer()
            }

        } // End appDidEnterForeground

    } // End Class 