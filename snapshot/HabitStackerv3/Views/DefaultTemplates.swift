import Foundation
import OSLog

// MARK: - Template Models

/// Represents a pre-configured task template for onboarding
struct DefaultTaskTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let suggestedDuration: Int // minutes
    let suggestedPriority: Int // 1-3 matching TaskPriority raw values
    let repetitionIntervalDays: Int
    
    init(name: String, suggestedDuration: Int, suggestedPriority: TaskPriority, repetitionIntervalDays: Int) {
        self.id = UUID()
        self.name = name
        self.suggestedDuration = suggestedDuration
        self.suggestedPriority = suggestedPriority.rawValue
        self.repetitionIntervalDays = repetitionIntervalDays
    }
    
    // Custom coding keys to handle ID generation
    enum CodingKeys: String, CodingKey {
        case name, suggestedDuration, suggestedPriority, repetitionIntervalDays
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID() // Generate new ID when decoding
        self.name = try container.decode(String.self, forKey: .name)
        self.suggestedDuration = try container.decode(Int.self, forKey: .suggestedDuration)
        self.suggestedPriority = try container.decode(Int.self, forKey: .suggestedPriority)
        self.repetitionIntervalDays = try container.decode(Int.self, forKey: .repetitionIntervalDays)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(suggestedDuration, forKey: .suggestedDuration)
        try container.encode(suggestedPriority, forKey: .suggestedPriority)
        try container.encode(repetitionIntervalDays, forKey: .repetitionIntervalDays)
    }
    
    enum TaskPriority: Int, Codable, CaseIterable {
        case nonEssential = 1
        case core = 2
        case essential = 3
        
        var displayName: String {
            switch self {
            case .nonEssential: return "Non-Essential"
            case .core: return "Core"
            case .essential: return "Essential"
            }
        }
    }
    
    // Helper computed property to get TaskPriority enum
    var priority: TaskPriority {
        return TaskPriority(rawValue: suggestedPriority) ?? .core
    }
}

/// JSON representation of a routine template
private struct RoutineTemplateJSON: Codable {
    let name: String
    let description: String
    let taskNames: [String]
}

/// Represents a pre-configured routine template
struct DefaultRoutineTemplate: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let taskNames: [String]
    var tasks: [DefaultTaskTemplate] = [] // Populated after loading
    
    init(name: String, description: String, taskNames: [String]) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.taskNames = taskNames
    }
}

// MARK: - Default Templates Data

struct DefaultTemplates {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DefaultTemplates")
    
    // Lazy-loaded templates from JSON
    static let templates: [DefaultRoutineTemplate] = {
        loadRoutineTemplates()
    }()
    
    // Lazy-loaded individual tasks from JSON
    static let tasks: [DefaultTaskTemplate] = {
        loadTaskTemplates()
    }()
    
    // Load routine templates from JSON file
    private static func loadRoutineTemplates() -> [DefaultRoutineTemplate] {
        guard let url = Bundle.main.url(forResource: "template_routines", withExtension: "json") else {
            logger.error("Could not find template_routines.json in bundle")
            return fallbackRoutineTemplates()
        }
        
        do {
            let data = try Data(contentsOf: url)
            let jsonTemplates = try JSONDecoder().decode([RoutineTemplateJSON].self, from: data)
            
            // Load task templates to match task names with tasks
            let taskDictionary = createTaskDictionary()
            
            // Convert JSON templates to DefaultRoutineTemplate with populated tasks
            var templates: [DefaultRoutineTemplate] = []
            for jsonTemplate in jsonTemplates {
                var template = DefaultRoutineTemplate(
                    name: jsonTemplate.name,
                    description: jsonTemplate.description,
                    taskNames: jsonTemplate.taskNames
                )
                
                // Populate tasks based on task names
                template.tasks = jsonTemplate.taskNames.compactMap { taskName in
                    if let task = taskDictionary[taskName] {
                        return task
                    } else {
                        logger.warning("Task '\(taskName)' referenced in routine '\(template.name)' not found in tasks.json")
                        return nil
                    }
                }
                
                templates.append(template)
            }
            
            logger.info("Successfully loaded \(templates.count) routine templates from JSON")
            return templates
        } catch {
            logger.error("Failed to load routine templates from JSON: \(error.localizedDescription)")
            return fallbackRoutineTemplates()
        }
    }
    
    // Create a dictionary of task names to task templates for quick lookup
    private static func createTaskDictionary() -> [String: DefaultTaskTemplate] {
        var dictionary: [String: DefaultTaskTemplate] = [:]
        for task in tasks {
            dictionary[task.name] = task
        }
        return dictionary
    }
    
    // Load individual task templates from JSON file
    private static func loadTaskTemplates() -> [DefaultTaskTemplate] {
        guard let url = Bundle.main.url(forResource: "template_tasks", withExtension: "json") else {
            logger.error("Could not find template_tasks.json in bundle")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let tasks = try JSONDecoder().decode([DefaultTaskTemplate].self, from: data)
            logger.info("Successfully loaded \(tasks.count) task templates from JSON")
            return tasks
        } catch {
            logger.error("Failed to load task templates from JSON: \(error.localizedDescription)")
            return []
        }
    }
    
    // Fallback templates in case JSON loading fails
    private static func fallbackRoutineTemplates() -> [DefaultRoutineTemplate] {
        return [
            DefaultRoutineTemplate(
                name: "Morning Routine",
                description: "Start your day with essential morning tasks",
                taskNames: ["Make Bed", "Drink Water", "Breakfast", "Brush Teeth"]
            )
        ]
    }
}