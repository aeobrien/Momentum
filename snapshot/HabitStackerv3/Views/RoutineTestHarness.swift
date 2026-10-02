import Foundation
import CoreData

// MARK: - TestResult Definition


// MARK: - RoutineTestHarness Class
class RoutineTestHarness {
    
    struct TestResult {
        let routine: CDRoutine
            let scheduledTasks: [ScheduledTask]
            let originalConfigs: [TestTaskConfig]
            
        var analysis: String {
                """
                Test Results:
                ------------
                Routine: \(routine.name ?? "Unnamed CD Routine")
                
                Tasks Scheduled: \(scheduledTasks.count)/\(originalConfigs.count)
                Essential Tasks: \(scheduledTasks.filter { $0.task.essentiality == 3 }.count)
                Core Tasks: \(scheduledTasks.filter { $0.task.essentiality == 2 }.count)
                Optional Tasks: \(scheduledTasks.filter { $0.task.essentiality == 1 }.count)
                
                Time Utilization: \(scheduledTasks.reduce(0.0) { $0 + $1.allocatedDuration }/60) minutes
                
                Task Distribution:
                \(scheduledTasks.enumerated().map { index, task in
                    "[\(index + 1)] \(task.task.taskName) (E\(task.task.essentiality ?? 0)) - \(Int(task.allocatedDuration/60))m"
                }.joined(separator: "\n"))
                """
            }
        
        private func isTaskDue(_ config: RoutineTestHarness.TestTaskConfig) -> Bool {
            guard let lastCompleted = config.lastCompleted,
                  config.repetitionInterval > 0 else {
                return true // Tasks with no interval or never completed are always due
            }
            
            let timeSinceCompletion = Date().timeIntervalSince(lastCompleted)
            return timeSinceCompletion >= Double(config.repetitionInterval)
        }
    }
    // Configuration Types
        struct RandomTestConfig {
            let numberOfTasks: Int
            let minAvailableTime: TimeInterval
            let maxAvailableTime: TimeInterval
            
            static let `default` = RandomTestConfig(
                numberOfTasks: 15,
                minAvailableTime: 1800,  // 30 minutes
                maxAvailableTime: 14400  // 4 hours
            )
        }
    
    struct TaskRange {
        let fixedDurations: [Int] = [1, 2, 5, 10, 15, 20, 25, 30] // Common fixed durations
        let variableDurationRanges: [(min: Int, max: Int)] = [
            (5, 15),  // Small variation
            (10, 25), // Medium variation
            (15, 45), // Large variation
            (20, 60)  // Extra large variation
        ]
        let repetitionDays: [Int]
        let lastCompletedDaysAgo: ClosedRange<Int>
        let completionProbability: Double
        
        static let `default` = TaskRange(
            repetitionDays: [1, 2, 3, 7, 14, 30, 90],
            lastCompletedDaysAgo: 0...90,
            completionProbability: 0.8
        )
    }
    
    struct TestTaskConfig {
        let name: String
        let essentiality: Int16
        let minDuration: Int32  // Changed from single duration to min/max
        let maxDuration: Int32
        let lastCompleted: Date?
        let repetitionInterval: Int32
        let dependsOn: Set<String>
        
        var isVariableDuration: Bool {
            minDuration != maxDuration
        }
    }
    
    struct TestRoutineConfig {
            let name: String
            let tasks: [TestTaskConfig]
            let targetDuration: TimeInterval
            let lastUsed: Date
            let totalCompletions: Int
            let averageCompletionTime: Double
        }
    
    private let viewContext: NSManagedObjectContext
        private let logger = AppLogger.create(subsystem: "com.app.TestHarness", category: "Testing")
        
        init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
            self.viewContext = context
        }
    
    private func performInBackground(_ block: @escaping (NSManagedObjectContext) throws -> Void) throws {
        let context = CoreDataStack.shared.newBackgroundContext()
        try context.performAndWait {
            try block(context)
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func clearTestData() throws {
            // Create a new background context for deletion
            let backgroundContext = CoreDataStack.shared.newBackgroundContext()
            
            try backgroundContext.performAndWait {
                do {
                    // First, fetch and delete all relationships
                    let relationRequest: NSFetchRequest<CDRoutineTask> = CDRoutineTask.fetchRequest()
                    let relations = try backgroundContext.fetch(relationRequest)
                    
                    for relation in relations {
                        backgroundContext.delete(relation)
                    }
                    
                    // Save after deleting relationships
                    try backgroundContext.save()
                    
                    // Now delete routines and tasks
                    let routineRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
                    let taskRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
                    
                    let routines = try backgroundContext.fetch(routineRequest)
                    let tasks = try backgroundContext.fetch(taskRequest)
                    
                    for routine in routines {
                        backgroundContext.delete(routine)
                    }
                    
                    for task in tasks {
                        backgroundContext.delete(task)
                    }
                    
                    // Final save
                    try backgroundContext.save()
                    
                    self.logger.info("Successfully cleared test data")
                } catch {
                    self.logger.error("Failed to clear test data", error: error)
                    throw error
                }
            }
        }
    
    private func createTestRoutine(with config: TestRoutineConfig) throws -> CDRoutine {
        let routine = CDRoutine(context: viewContext)
        routine.uuid = UUID()
        routine.name = config.name
        routine.createdOn = Date()
        routine.lastUsed = config.lastUsed
        routine.totalCompletions = Int32(config.totalCompletions)
        routine.averageCompletionTime = config.averageCompletionTime
        
        // Create and save tasks
        var createdTasks: [(CDTask, Int)] = []
        var taskSummary: [(name: String, essentiality: Int16, duration: String)] = []
        
        try viewContext.performAndWait {
            for (index, taskConfig) in config.tasks.enumerated() {
                let task = CDTask(context: viewContext)
                task.uuid = UUID()
                task.taskName = taskConfig.name
                task.essentiality = taskConfig.essentiality
                task.minDuration = taskConfig.minDuration
                task.maxDuration = taskConfig.maxDuration
                task.lastCompleted = taskConfig.lastCompleted
                task.repetitionInterval = taskConfig.repetitionInterval
                
                createdTasks.append((task, index))
                taskSummary.append((
                    taskConfig.name,
                    taskConfig.essentiality,
                    taskConfig.minDuration == taskConfig.maxDuration ?
                        "\(taskConfig.minDuration)m" :
                        "\(taskConfig.minDuration)-\(taskConfig.maxDuration)m"
                ))
            }
            
            // Single summary log for task creation
            self.logger.debug("""
                Created \(createdTasks.count) tasks:
                \(taskSummary.map { "[\($0.name)] E:\($0.essentiality) D:\($0.duration)" }.joined(separator: "\n"))
                Task numbers: \(createdTasks.map { String($0.1 + 1) }.joined(separator: ","))
                """)
            
            try viewContext.save()
            
            // Create relationships with single summary log
            for (task, index) in createdTasks {
                let relation = CDRoutineTask(context: viewContext)
                relation.order = Int32(index)
                relation.task = task
                relation.routine = routine
            }
            
            self.logger.debug("Created \(createdTasks.count) task relations")
            
            try viewContext.save()
        }
        
        return routine
    }
    
    func generateRandomTasks(count: Int, taskRange: TaskRange) -> [TestTaskConfig] {
            var tasks: [TestTaskConfig] = []
            
            // Calculate how many variable duration tasks we want (10% rounded up)
            let variableDurationCount = Int(ceil(Double(count) * 0.1))
            var remainingVariableTasks = variableDurationCount
            
            // Ensure at least one task of each essentiality level
            for essentiality in [3, 2, 1] {
                // 33% chance for each essential task to be variable duration if we still need them
                let forceVariable = remainingVariableTasks > 0 && Double.random(in: 0...1) < 0.33
                tasks.append(generateRandomTask(
                    name: "Task \(tasks.count + 1)",
                    essentiality: Int16(essentiality),
                    taskRange: taskRange,
                    forceVariableDuration: forceVariable
                ))
                if forceVariable {
                    remainingVariableTasks -= 1
                }
            }
            
            // Generate remaining tasks
            while tasks.count < count {
                let essentiality = Int16.random(in: 1...3)
                // Force variable duration if we still need more
                let forceVariable = remainingVariableTasks > 0 &&
                    Double(count - tasks.count) <= Double(remainingVariableTasks)
                
                tasks.append(generateRandomTask(
                    name: "Task \(tasks.count + 1)",
                    essentiality: Int16(essentiality),
                    taskRange: taskRange,
                    forceVariableDuration: forceVariable
                ))
                
                if forceVariable {
                    remainingVariableTasks -= 1
                }
            }
            
            // Add random dependencies (20% chance for each task to depend on a previous task)
            return tasks.enumerated().map { index, task in
                var dependsOn = Set<String>()
                if index > 0 && Double.random(in: 0...1) < 0.2 {
                    // Can only depend on earlier tasks to avoid cycles
                    let possibleDependencies = tasks[0..<index]
                    if let dependency = possibleDependencies.randomElement() {
                        dependsOn.insert(dependency.name)
                    }
                }
                
                return TestTaskConfig(
                    name: task.name,
                    essentiality: task.essentiality,
                    minDuration: task.minDuration,
                    maxDuration: task.maxDuration,
                    lastCompleted: task.lastCompleted,
                    repetitionInterval: task.repetitionInterval,
                    dependsOn: dependsOn
                )
            }
        }
    
    private func generateRandomTask(
            name: String,
            essentiality: Int16,
            taskRange: TaskRange,
            forceVariableDuration: Bool = false
        ) -> TestTaskConfig {
            let isVariableDuration = forceVariableDuration || Double.random(in: 0...1) < 0.1
            
            let (minDuration, maxDuration): (Int32, Int32)
            if isVariableDuration {
                let range = taskRange.variableDurationRanges.randomElement()!
                minDuration = Int32(range.min)
                maxDuration = Int32(range.max)
            } else {
                let duration = Int32(taskRange.fixedDurations.randomElement()!)
                minDuration = duration
                maxDuration = duration
            }
            
            let hasBeenCompleted = Double.random(in: 0...1) < taskRange.completionProbability
            
            let lastCompleted: Date?
            let repetitionInterval: Int32
            
            if hasBeenCompleted {
                let daysAgo = Int.random(in: taskRange.lastCompletedDaysAgo)
                lastCompleted = Calendar.current.date(
                    byAdding: .day,
                    value: -daysAgo,
                    to: Date()
                )
                
                let repeatDays = taskRange.repetitionDays.randomElement() ?? 1
                repetitionInterval = Int32(repeatDays * 86400)
            } else {
                lastCompleted = nil
                repetitionInterval = 0
            }
            
            return TestTaskConfig(
                name: name,
                essentiality: essentiality,
                minDuration: minDuration,
                maxDuration: maxDuration,
                lastCompleted: lastCompleted,
                repetitionInterval: repetitionInterval,
                dependsOn: Set<String>()
            )
        }
    
    func runRandomTest(
        config: RandomTestConfig = .default,
        taskRange: TaskRange = .default
    ) throws -> TestResult {
        let modifiedConfig = RandomTestConfig(
            numberOfTasks: config.numberOfTasks,
            minAvailableTime: 240 * 60,  // 180 minutes in seconds
            maxAvailableTime: 240 * 60   // Fixed at 180 minutes
        )
        
        // Rest of the implementation remains the same
        try clearTestData()
        
        let tasks = generateRandomTasks(count: config.numberOfTasks, taskRange: taskRange)
        let availableTime = Double.random(
            in: modifiedConfig.minAvailableTime...modifiedConfig.maxAvailableTime
        )
        
        let routineConfig = TestRoutineConfig(
            name: "Random Test Routine \(UUID().uuidString.prefix(8))",
            tasks: tasks,
            targetDuration: availableTime,
            lastUsed: Date(),
            totalCompletions: Int.random(in: 0...50),
            averageCompletionTime: Double.random(in: 1800...7200)
        )
        
        let routine = try createTestRoutine(with: routineConfig)
        return try runTest(with: routine)
    }
    
    // We need to implement the runTest method
    private func runTest(with routine: CDRoutine) throws -> TestResult {
           logger.info("Starting test for routine: \(routine.name ?? "")")
           
           // Get tasks that are due (with condensed logging)
           let relations = routine.taskRelations?.allObjects as? [CDRoutineTask] ?? []
           let sortedRelations = relations.sorted { $0.order < $1.order }
           
           var dueCount = 0
           var notDueCount = 0
           let dueTasks = sortedRelations.compactMap { relation -> CDTask? in
               guard let task = relation.task else { return nil }
               
               if isTaskDue(task) {
                   dueCount += 1
                   return task
               } else {
                   notDueCount += 1
                   return nil
               }
           }
           
           logger.info("""
               Task eligibility summary:
               Total tasks: \(sortedRelations.count)
               Due tasks: \(dueCount)
               Not due: \(notDueCount)
               """)
           
           // Use new variable duration scheduler
           let scheduler = VariableDurationScheduler()
           let (scheduledTasks, durations) = scheduler.schedule(tasks: dueTasks, availableTime: 120)
           
           logger.info("Scheduled \(scheduledTasks.count) of \(dueTasks.count) due tasks")
           
           // Prepare TestResult using the updated ScheduledTask struct
           let resultSchedule = scheduledTasks.map {
               ScheduledTask(
                   task: $0, // Use CDTask directly
                   allocatedDuration: TimeInterval(durations[$0.uuid?.uuidString ?? ""] ?? Int($0.minDuration)) * 60
                   // Removed: isFlexible: $0.minDuration != $0.maxDuration
               )
           }

           // Convert CDRoutine to Routine for TestResult (if needed, or adjust TestResult)
           // For now, assume toDomainModel exists or adjust TestResult struct
           // let domainRoutine = routine.toDomainModel() // Assuming this conversion exists

           return TestResult(
               routine: routine, // Pass CDRoutine directly
               scheduledTasks: resultSchedule,
               originalConfigs: sortedRelations.compactMap { relation -> TestTaskConfig? in
                   guard let task = relation.task else { return nil }
                   return TestTaskConfig(
                       name: task.taskName ?? "",
                       essentiality: task.essentiality,
                       minDuration: task.minDuration,
                       maxDuration: task.maxDuration,
                       lastCompleted: task.lastCompleted,
                       repetitionInterval: task.repetitionInterval,
                       dependsOn: Set<String>()
                   )
               }
           )
       }
    
    private func scheduleTasksWithPriority(_ tasks: [CDTask], availableTime: Int) -> [CDTask] {
        let bufferTime = 10
        var remainingTime = availableTime - bufferTime
        var scheduledTasks: [CDTask] = []
        
        logger.info("""
            Starting scheduling with:
            Total time: \(availableTime) minutes
            Buffer: \(bufferTime) minutes
            Available: \(remainingTime) minutes
            """)
        
        // 1. Essential Tasks First (Must do these)
        let essentialTasks = tasks.filter { $0.essentiality == 3 }
        let totalEssentialTime = essentialTasks.reduce(into: 0) { result, task in
            result += Int(task.minDuration)
        }
        
        logger.info("Essential tasks require \(totalEssentialTime) minutes")
        
        guard totalEssentialTime <= remainingTime else {
            logger.error("Insufficient time for essential tasks (\(totalEssentialTime) needed, \(remainingTime) available)")
            return []
        }
        
        // Schedule all essential tasks first
        for task in essentialTasks {
            scheduledTasks.append(task)
            remainingTime -= Int(task.minDuration)
            logger.info("Scheduled essential task: \(task.taskName ?? "") (\(task.minDuration) min)")
        }
        
        logger.info("After essential tasks: \(remainingTime) minutes remaining")
        
        // 2. Score and Sort Remaining Tasks
        let nonEssentialTasks = tasks.filter { $0.essentiality != 3 }
        let scoredTasks = nonEssentialTasks.map { task -> (CDTask, Double) in
            let baseScore = task.essentiality == 2 ? 100.0 : 10.0
            let neverCompletedBoost = task.lastCompleted == nil ? baseScore * 0.5 : 0.0
            
            var overdueFactor = 1.0
            if let lastCompleted = task.lastCompleted,
               task.repetitionInterval > 0 {
                let timeSince = Date().timeIntervalSince(lastCompleted)
                let interval = Double(task.repetitionInterval)
                overdueFactor = pow(timeSince / interval, 1.5)
            }
            
            let finalScore = (baseScore + neverCompletedBoost) * overdueFactor
            
            logger.debug("""
                PriorityCalc \(task.taskName ?? ""): Base: \(baseScore), NCB: \(neverCompletedBoost), OF: \(overdueFactor), FS: \(finalScore), D: \(task.minDuration) mins
                """)
                
            return (task, finalScore)
        }
        .sorted { $0.1 > $1.1 }
        
        // 3. Schedule Remaining Tasks by Priority
        for (task, score) in scoredTasks {
            let duration = Int(task.minDuration)
            if duration <= remainingTime {
                scheduledTasks.append(task)
                remainingTime -= duration
                logger.info("Scheduled task: \(task.taskName ?? "") (score: \(score), duration: \(duration)min)")
            } else {
                logger.debug("Skipping task: \(task.taskName ?? "") (requires \(duration)min, have \(remainingTime)min)")
            }
        }
        
        logger.info("""
            Scheduling complete:
            Tasks scheduled: \(scheduledTasks.count)
            Time remaining: \(remainingTime) minutes
            Buffer maintained: \(bufferTime) minutes
            """)
        
        return scheduledTasks
    }
    
    private func isTaskDue(_ task: CDTask) -> Bool {
            guard let lastCompleted = task.lastCompleted,
                  task.repetitionInterval > 0 else {
                self.logger.debug("Task \(task.taskName ?? "") is due (no completion history or interval)")
                return true // Task has never been completed or has no interval
            }
            
            let timeSinceCompletion = Date().timeIntervalSince(lastCompleted)
            let isDue = timeSinceCompletion >= Double(task.repetitionInterval)
            
            self.logger.debug("""
                Due check: \(task.taskName ?? ""): LC: \(lastCompleted), I: \(task.repetitionInterval) seconds, TSC: \(Int(timeSinceCompletion / 86400)) days, Due: \(isDue)
                """)
            
            return isDue
        }

        
}

// MARK: - RoutineTestHarness Extension
extension RoutineTestHarness {
    /// Runs multiple random tests and aggregates the results
    /// Runs multiple random tests and aggregates the results
    func runRandomTestBatch(
        count: Int,
        config: RandomTestConfig = .default
    ) throws -> String {
        var results: [TestResult] = []
        var totalTasksScheduled = 0
        var totalTasksEligible = 0
        var essentialityDistribution = [1: 0, 2: 0, 3: 0]
        var averageTimeUtilization = 0.0
        
        self.logger.info("Starting batch test with \(count) iterations")
        
        for i in 1...count {
            self.logger.debug("Running test iteration \(i)/\(count)")
            
            let result = try runRandomTest(config: config)
            results.append(result)
            
            // Analyze results
            let scheduledTasks = result.scheduledTasks.count
            totalTasksScheduled += scheduledTasks
            
            // Count eligible tasks
            let eligibleTasks = result.originalConfigs.filter { config in
                guard let lastCompleted = config.lastCompleted,
                      config.repetitionInterval > 0 else { return true }
                let timeSinceCompletion = Date().timeIntervalSince(lastCompleted)
                return timeSinceCompletion >= Double(config.repetitionInterval)
            }.count
            totalTasksEligible += eligibleTasks
            
            // Track essentiality distribution in scheduled tasks
            for task in result.scheduledTasks {
                let essentiality = task.task.essentiality
                essentialityDistribution[Int(essentiality), default: 0] += 1
            }
            
            // Track time utilization
            let totalTime = result.scheduledTasks.reduce(0.0) { $0 + $1.allocatedDuration }
            averageTimeUtilization += totalTime
        }
        
        // Calculate averages
        let avgTasksScheduled = Double(totalTasksScheduled) / Double(count)
        let avgTasksEligible = Double(totalTasksEligible) / Double(count)
        averageTimeUtilization /= Double(count)
        
        self.logger.info("Completed batch test. Average tasks scheduled: \(avgTasksScheduled)")
        
        return """
                Random Test Batch Summary
                ------------------------
                Total Tests Run: \(count)
                Average Tasks Scheduled: \(String(format: "%.2f", avgTasksScheduled))
                Average Eligible Tasks: \(String(format: "%.2f", avgTasksEligible))
                Average Time Utilization: \(String(format: "%.1f", averageTimeUtilization/60)) minutes
                
                Task Distribution by Essentiality:
                Essential (3): \(essentialityDistribution[3] ?? 0) tasks
                Core (2): \(essentialityDistribution[2] ?? 0) tasks
                Optional (1): \(essentialityDistribution[1] ?? 0) tasks
                
                Essential Task Ratio: \(String(format: "%.1f%%", Double(essentialityDistribution[3] ?? 0) / Double(totalTasksScheduled) * 100))
                Core Task Ratio: \(String(format: "%.1f%%", Double(essentialityDistribution[2] ?? 0) / Double(totalTasksScheduled) * 100))
                Optional Task Ratio: \(String(format: "%.1f%%", Double(essentialityDistribution[1] ?? 0) / Double(totalTasksScheduled) * 100))
                
                Individual Test Results:
                ----------------------
                \(results.enumerated().map { index, result in
                    """
                    Test \(index + 1):
                    \(result.analysis)
                    
                    """
                }.joined())
                """
    }
    
#if DEBUG
    /// Additional testing utilities for debug builds
    
    /// Verifies the integrity of all relationships in the database
    func verifyDatabaseIntegrity() throws -> String {
        var report = "Database Integrity Report\n"
        report += "------------------------\n"
        
        // Check Routines
        let routineRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        let routines = try viewContext.fetch(routineRequest)
        report += "Total Routines: \(routines.count)\n\n"
        
        for routine in routines {
            report += "Routine: \(routine.name ?? "Unnamed")\n"
            let relations = routine.taskRelations?.allObjects as? [CDRoutineTask] ?? []
            report += "- Task Relations: \(relations.count)\n"
            
            // Verify each relation
            for relation in relations {
                if let task = relation.task {
                    report += "  - Task: \(task.taskName ?? "Unnamed") (Order: \(relation.order))\n"
                } else {
                    report += "  - ERROR: Relation without task (Order: \(relation.order))\n"
                }
            }
            report += "\n"
        }
        
        // Check Tasks
        let taskRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        let tasks = try viewContext.fetch(taskRequest)
        report += "Total Tasks: \(tasks.count)\n\n"
        
        for task in tasks {
            report += "Task: \(task.taskName ?? "Unnamed")\n"
            let relations = task.routineRelations?.allObjects as? [CDRoutineTask] ?? []
            report += "- Used in \(relations.count) routines\n"
            
            // Verify each routine reference
            for relation in relations {
                if let routine = relation.routine {
                    report += "  - Routine: \(routine.name ?? "Unnamed") (Order: \(relation.order))\n"
                } else {
                    report += "  - ERROR: Relation without routine\n"
                }
            }
            report += "\n"
        }
        
        return report
    }
    
    /// Generates a performance report for the test system
    func generatePerformanceReport() -> String {
        // Add performance metrics collection and reporting
        // This is a placeholder for future implementation
        return "Performance Report Placeholder"
    }
    #endif
}

// MARK: - Extended Test Configuration
extension RoutineTestHarness {
    struct OptimizationTestConfig {
        let availableTime: Int
        let taskCount: Int
        let essentialTaskCount: Int
        
        static let standard = OptimizationTestConfig(
            availableTime: Int.random(in: 45...120),
            taskCount: 15,
            essentialTaskCount: 3
        )
    }
    
    func runOptimizationTest(config: OptimizationTestConfig = .standard) throws -> String {
        let optimizer = ScheduleOptimizer()
        let tasks = try generateTestTasks(count: config.taskCount, essentialCount: config.essentialTaskCount)
        
        let logger = AppLogger.create(subsystem: "com.app.TestHarness", category: "OptimizationTest")
        logger.info("""
            Starting optimization test:
            - Available time: \(config.availableTime) minutes
            - Total tasks: \(config.taskCount)
            - Essential tasks: \(config.essentialTaskCount)
            """)
        
        let optimizedSchedule = try optimizer.createOptimizedSchedule(
            tasks: tasks,
            availableTime: config.availableTime
        )
        
        return generateTestReport(
            originalTasks: tasks,
            scheduledTasks: optimizedSchedule,
            availableTime: config.availableTime
        )
    }
    
    private func generateTestReport(
        originalTasks: [CDTask],
        scheduledTasks: [CDTask],
        availableTime: Int
    ) -> String {
        """
        Optimization Test Report
        ======================
        Available Time: \(availableTime) minutes
        
        Original Tasks: \(originalTasks.count)
        - Essential: \(originalTasks.filter { $0.essentiality == 3 }.count)
        - Core: \(originalTasks.filter { $0.essentiality == 2 }.count)
        - Non-Essential: \(originalTasks.filter { $0.essentiality == 1 }.count)
        
        Scheduled Tasks: \(scheduledTasks.count)
        - Essential: \(scheduledTasks.filter { $0.essentiality == 3 }.count)
        - Core: \(scheduledTasks.filter { $0.essentiality == 2 }.count)
        - Non-Essential: \(scheduledTasks.filter { $0.essentiality == 1 }.count)
        
        Total Scheduled Time: \(scheduledTasks.reduce(0) { $0 + Int($1.minDuration) }) minutes
        Remaining Time: \(availableTime - scheduledTasks.reduce(0) { $0 + Int($1.minDuration) }) minutes
        
        Scheduled Tasks Details:
        \(scheduledTasks.enumerated().map { index, task in
            """
            \(index + 1). \(task.taskName ?? "Unknown")
               - Duration: \(task.minDuration)m
               - Essentiality: \(task.essentiality)
               - Last Completed: \(task.lastCompleted?.description ?? "Never")
            """
        }.joined(separator: "\n"))
        """
    }
}

extension RoutineTestHarness {
    private func generateTestTasks(count: Int, essentialCount: Int) throws -> [CDTask] {
            let backgroundContext = CoreDataStack.shared.newBackgroundContext()
            var tasks: [CDTask] = []
            
            try backgroundContext.performAndWait {
                // Generate essential tasks first
                for i in 0..<essentialCount {
                    let task = CDTask(context: backgroundContext)
                    task.uuid = UUID()
                    task.taskName = "Essential Task \(i + 1)"
                    task.essentiality = 3
                    task.minDuration = Int32.random(in: 5...30)
                    task.maxDuration = task.minDuration
                    task.repetitionInterval = Int32(86400)  // 1 day
                    tasks.append(task)
                }
                
                // Generate remaining tasks
                for i in essentialCount..<count {
                    let task = CDTask(context: backgroundContext)
                    task.uuid = UUID()
                    task.taskName = "Task \(i + 1)"
                    task.essentiality = Int16.random(in: 1...2)
                    task.minDuration = Int32.random(in: 5...30)
                    task.maxDuration = task.minDuration
                    
                    // Random completion history
                    if Double.random(in: 0...1) < 0.7 {
                        task.lastCompleted = Calendar.current.date(
                            byAdding: .day,
                            value: -Int.random(in: 1...30),
                            to: Date()
                        )
                        task.repetitionInterval = Int32([1, 2, 3, 7, 14, 30].randomElement() ?? 1 * 86400)
                    }
                    
                    tasks.append(task)
                }
                
                try backgroundContext.save()
            }
            
            return tasks
        }
}

