import Foundation
import CoreData

/// Handles the creation of routines from templates and user selections
class RoutineBuilder {
    private let taskStorage: TaskStorageCoreData
    private let routineStorage: RoutineStorage
    private let context: NSManagedObjectContext
    
    init() {
        self.taskStorage = TaskStorageCoreData()
        self.routineStorage = RoutineStorage.shared
        self.context = DataStoreManager.shared.viewContext
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
    func createTasksFromTemplates(_ templates: [DefaultTaskTemplate], in context: NSManagedObjectContext) throws -> [String] {
        var taskUUIDs: [String] = []
        
        for template in templates {
            let task = CustomTask(
                taskName: template.name,
                essentiality: template.suggestedPriority.rawValue,
                minDuration: template.suggestedDuration,
                maxDuration: template.suggestedDuration,
                repetitionInterval: template.repetitionIntervalDays > 0 ? template.repetitionIntervalDays * 86400 : 0,
                isSessionTask: template.repetitionIntervalDays == 0,
                shouldTrackAverageTime: true
            )
            
            let result = taskStorage.createTask(task, in: context)
            switch result {
            case .success(let createdTask):
                taskUUIDs.append(createdTask.uuid)
            case .failure(let error):
                throw error
            }
        }
        
        return taskUUIDs
    }
    
    /// Creates tasks from custom entries
    func createTasksFromCustomEntries(_ entries: [CustomTaskEntry], in context: NSManagedObjectContext) throws -> [String] {
        var taskUUIDs: [String] = []
        
        for entry in entries where !entry.name.isEmpty {
            let task = CustomTask(
                taskName: entry.name,
                essentiality: entry.priority.rawValue,
                minDuration: entry.duration,
                maxDuration: entry.duration,
                repetitionInterval: entry.repetitionIntervalDays > 0 ? entry.repetitionIntervalDays * 86400 : 0,
                isSessionTask: entry.repetitionIntervalDays == 0,
                shouldTrackAverageTime: true
            )
            
            let result = taskStorage.createTask(task, in: context)
            switch result {
            case .success(let createdTask):
                taskUUIDs.append(createdTask.uuid)
            case .failure(let error):
                throw error
            }
        }
        
        return taskUUIDs
    }
    
    /// Creates a routine from selected templates and custom tasks
    func createRoutine(
        name: String,
        selectedTemplates: [DefaultTaskTemplate],
        customEntries: [CustomTaskEntry] = [],
        in context: NSManagedObjectContext
    ) throws -> Routine {
        // Create tasks from templates
        let templateTaskUUIDs = try createTasksFromTemplates(selectedTemplates, in: context)
        
        // Create tasks from custom entries
        let customTaskUUIDs = try createTasksFromCustomEntries(customEntries, in: context)
        
        // Combine all task UUIDs
        let allTaskUUIDs = templateTaskUUIDs + customTaskUUIDs
        
        // Create the routine
        let routine = Routine(
            id: UUID().uuidString,
            name: name,
            createdOn: Date(),
            taskUUIDs: allTaskUUIDs,
            metadata: RoutineMetadata(
                lastUsed: nil,
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
    func taskExists(withName name: String, in context: NSManagedObjectContext) -> Bool {
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
            essentiality: template.suggestedPriority.rawValue,
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
}