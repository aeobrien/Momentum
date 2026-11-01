import Foundation
import CoreData

/// Errors that can occur during routine building
enum RoutineBuilderError: LocalizedError {
    case duplicateTasks([String])
    
    var errorDescription: String? {
        switch self {
        case .duplicateTasks(let messages):
            return messages.joined(separator: "\n")
        }
    }
}

/// Handles the creation of routines from templates and user selections
class RoutineBuilder {
    private let taskStorage = TaskStorageCoreData.shared
    private let routineStorage = RoutineStorageCoreData.shared
    private var context: NSManagedObjectContext {
        DataStoreManager.shared.viewContext
    }
    
    /// Task template with selection state for UI
    struct SelectableTaskTemplate {
        let template: DefaultTaskTemplate
        var isSelected: Bool = true
        let taskId = UUID()
    }
    
    /// Custom task entry for user-added tasks
    struct CustomTaskEntry: Identifiable {
        let id = UUID()
        var name: String = ""
        var duration: Int = 10
        var priority: DefaultTaskTemplate.TaskPriority = .core
        var repetitionIntervalDays: Int = 0
    }
    
    /// Creates tasks from templates and returns their UUIDs
    func createTasksFromTemplates(_ templates: [DefaultTaskTemplate]) throws -> [String] {
        var taskUUIDs: [String] = []
        
        for template in templates {
            // Check if task already exists
            if let existingTaskUUID = findExistingTask(named: template.name) {
                taskUUIDs.append(existingTaskUUID)
            } else {
                // Create new task
                let task = CustomTask(
                    taskName: template.name,
                    essentiality: template.suggestedPriority,
                    minDuration: template.suggestedDuration,
                    maxDuration: template.suggestedDuration,
                    repetitionInterval: template.repetitionIntervalDays > 0 ? template.repetitionIntervalDays * 86400 : 0,
                    isSessionTask: template.repetitionIntervalDays == 0,
                    shouldTrackAverageTime: true
                )
                
                let result = taskStorage.createTask(task)
                switch result {
                case .success(let createdTask):
                    taskUUIDs.append(createdTask.uuid)
                case .failure(let error):
                    throw error
                }
            }
        }
        
        return taskUUIDs
    }
    
    /// Creates tasks from custom entries
    func createTasksFromCustomEntries(_ entries: [CustomTaskEntry]) throws -> [String] {
        var taskUUIDs: [String] = []
        var errors: [String] = []
        
        for entry in entries where !entry.name.isEmpty {
            // Check if task already exists
            if let existingTaskUUID = findExistingTask(named: entry.name) {
                errors.append("Task '\(entry.name)' already exists")
                continue
            }
            
            let task = CustomTask(
                taskName: entry.name,
                essentiality: entry.priority.rawValue,
                minDuration: entry.duration,
                maxDuration: entry.duration,
                repetitionInterval: entry.repetitionIntervalDays > 0 ? entry.repetitionIntervalDays * 86400 : 0,
                isSessionTask: entry.repetitionIntervalDays == 0,
                shouldTrackAverageTime: true
            )
            
            let result = taskStorage.createTask(task)
            switch result {
            case .success(let createdTask):
                taskUUIDs.append(createdTask.uuid)
            case .failure(let error):
                throw error
            }
        }
        
        // If there were duplicate task errors, throw them
        if !errors.isEmpty {
            throw RoutineBuilderError.duplicateTasks(errors)
        }
        
        return taskUUIDs
    }
    
    /// Creates a routine from selected templates and custom tasks
    func createRoutine(
        name: String,
        selectedTemplates: [DefaultTaskTemplate],
        customEntries: [CustomTaskEntry] = []
    ) throws -> Routine {
        // Create tasks from templates
        let templateTaskUUIDs = try createTasksFromTemplates(selectedTemplates)
        
        // Create tasks from custom entries
        let customTaskUUIDs = try createTasksFromCustomEntries(customEntries)
        
        // Combine all task UUIDs
        let allTaskUUIDs = templateTaskUUIDs + customTaskUUIDs
        
        // Create the routine
        let routine = Routine(
            id: UUID().uuidString,
            name: name,
            createdOn: Date(),
            taskUUIDs: allTaskUUIDs,
            metadata: RoutineMetadata(
                lastUsed: Date(),
                totalCompletions: 0,
                averageCompletionTime: 0
            )
        )
        
        // Save to routine storage
        let result = routineStorage.createRoutine(routine)
        switch result {
        case .success(let createdRoutine):
            return createdRoutine
        case .failure(let error):
            throw error
        }
    }
    
    /// Checks if a task with the given name already exists
    func taskExists(withName name: String) -> Bool {
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "taskName == %@", name)
        fetchRequest.fetchLimit = 1
        
        do {
            let count = try context.count(for: fetchRequest)
            return count > 0
        } catch {
            return false
        }
    }
    
    /// Finds an existing task by name and returns its UUID
    private func findExistingTask(named name: String) -> String? {
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "taskName == %@", name)
        fetchRequest.fetchLimit = 1
        
        do {
            if let task = try context.fetch(fetchRequest).first,
               let uuid = task.uuid {
                return uuid.uuidString
            }
        } catch {
            return nil
        }
        return nil
    }
    
    /// Gets or creates a task, returning its UUID
    func getOrCreateTask(from template: DefaultTaskTemplate) throws -> String {
        // Check if task already exists
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "taskName == %@", template.name)
        fetchRequest.fetchLimit = 1
        
        do {
            if let existingTask = try context.fetch(fetchRequest).first,
               let uuid = existingTask.uuid {
                return uuid.uuidString
            }
        } catch {
            // If fetch fails, continue to create new task
        }
        
        // Create new task
        let task = CustomTask(
            taskName: template.name,
            essentiality: template.suggestedPriority,
            minDuration: template.suggestedDuration,
            maxDuration: template.suggestedDuration,
            repetitionInterval: template.repetitionIntervalDays > 0 ? template.repetitionIntervalDays * 86400 : 0,
            isSessionTask: template.repetitionIntervalDays == 0,
            shouldTrackAverageTime: true
        )
        
        let result = taskStorage.createTask(task)
        switch result {
        case .success(let createdTask):
            return createdTask.uuid
        case .failure(let error):
            throw error
        }
    }
    
    /// Creates a routine with specific task order
    func createRoutineWithOrder(
        name: String,
        orderedTasks: [ReorderableTaskItem]
    ) throws -> Routine {
        var taskUUIDs: [String] = []
        
        for task in orderedTasks {
            if let template = task.originalTemplate {
                // Check if task already exists
                if let existingTaskUUID = findExistingTask(named: template.name) {
                    taskUUIDs.append(existingTaskUUID)
                } else {
                    // Create new task
                    let newTask = CustomTask(
                        taskName: template.name,
                        essentiality: template.suggestedPriority,
                        minDuration: template.suggestedDuration,
                        maxDuration: template.suggestedDuration,
                        repetitionInterval: template.repetitionIntervalDays > 0 ? template.repetitionIntervalDays * 86400 : 0,
                        isSessionTask: template.repetitionIntervalDays == 0,
                        shouldTrackAverageTime: true
                    )
                    
                    let result = taskStorage.createTask(newTask)
                    switch result {
                    case .success(let createdTask):
                        taskUUIDs.append(createdTask.uuid)
                    case .failure(let error):
                        throw error
                    }
                }
            } else if let custom = task.originalCustomEntry {
                // Check for duplicates
                if let existingTaskUUID = findExistingTask(named: custom.name) {
                    throw RoutineBuilderError.duplicateTasks(["Task '\(custom.name)' already exists"])
                }
                
                // Create custom task
                let newTask = CustomTask(
                    taskName: custom.name,
                    essentiality: custom.priority.rawValue,
                    minDuration: custom.duration,
                    maxDuration: custom.duration,
                    repetitionInterval: custom.repetitionIntervalDays > 0 ? custom.repetitionIntervalDays * 86400 : 0,
                    isSessionTask: custom.repetitionIntervalDays == 0,
                    shouldTrackAverageTime: true
                )
                
                let result = taskStorage.createTask(newTask)
                switch result {
                case .success(let createdTask):
                    taskUUIDs.append(createdTask.uuid)
                case .failure(let error):
                    throw error
                }
            }
        }
        
        // Create the routine with ordered task UUIDs
        let routine = Routine(
            id: UUID().uuidString,
            name: name,
            createdOn: Date(),
            taskUUIDs: taskUUIDs,
            metadata: RoutineMetadata(
                lastUsed: Date(),
                totalCompletions: 0,
                averageCompletionTime: 0
            )
        )
        
        // Save to routine storage
        let result = routineStorage.createRoutine(routine)
        switch result {
        case .success(let createdRoutine):
            return createdRoutine
        case .failure(let error):
            throw error
        }
    }
}