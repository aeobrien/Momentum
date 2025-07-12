import Foundation

// MARK: - Template Models

/// Represents a pre-configured task template for onboarding
struct DefaultTaskTemplate: Identifiable, Codable {
    let id = UUID()
    let name: String
    let suggestedDuration: Int // minutes
    let suggestedPriority: TaskPriority
    let repetitionIntervalDays: Int
    
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
}

/// Represents a pre-configured routine template
struct DefaultRoutineTemplate: Identifiable, Codable {
    let id = UUID()
    let name: String
    let description: String
    let tasks: [DefaultTaskTemplate]
}

// MARK: - Default Templates Data

struct DefaultTemplates {
    static let templates: [DefaultRoutineTemplate] = [
        DefaultRoutineTemplate(
            name: "Morning Routine",
            description: "Start your day with essential morning tasks",
            tasks: [
                DefaultTaskTemplate(name: "Open Curtains", suggestedDuration: 1, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Make Bed", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Drink Water", suggestedDuration: 1, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Meditation", suggestedDuration: 5, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Breakfast", suggestedDuration: 25, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Take Meds", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Shower/Shave", suggestedDuration: 10, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Brush Teeth", suggestedDuration: 4, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Get Dressed", suggestedDuration: 5, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Check Things", suggestedDuration: 5, suggestedPriority: .essential, repetitionIntervalDays: 1)
            ]
        ),
        
        DefaultRoutineTemplate(
            name: "Evening Routine",
            description: "Wind down and prepare for tomorrow",
            tasks: [
                DefaultTaskTemplate(name: "Tidy Front Room", suggestedDuration: 5, suggestedPriority: .core, repetitionIntervalDays: 1),
                DefaultTaskTemplate(name: "Empty Dishwasher", suggestedDuration: 10, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Stack and Run Dishwasher", suggestedDuration: 10, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Tidy Kitchen", suggestedDuration: 10, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Set for Breakfast", suggestedDuration: 5, suggestedPriority: .nonEssential, repetitionIntervalDays: 12),
                DefaultTaskTemplate(name: "Sleepy Tea", suggestedDuration: 3, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Fill Water Glass/Bottle", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 1),
                DefaultTaskTemplate(name: "Brush Teeth", suggestedDuration: 4, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Floss", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Prepare Clothes for Morning", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Put Phone on Charge", suggestedDuration: 5, suggestedPriority: .essential, repetitionIntervalDays: 1),
                DefaultTaskTemplate(name: "Put Watch on Charge", suggestedDuration: 1, suggestedPriority: .essential, repetitionIntervalDays: 1)
            ]
        ),
        
        DefaultRoutineTemplate(
            name: "Health & Hygiene",
            description: "Personal care and wellness tasks",
            tasks: [
                DefaultTaskTemplate(name: "Floss", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Mouthwash", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Shower/Shave", suggestedDuration: 10, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Deodorant", suggestedDuration: 1, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Moisturiser/Eye Cream", suggestedDuration: 2, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Hair Product", suggestedDuration: 1, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Dry Hair", suggestedDuration: 5, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Yoga", suggestedDuration: 10, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Meditation", suggestedDuration: 15, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Physio", suggestedDuration: 15, suggestedPriority: .essential, repetitionIntervalDays: 0)
            ]
        ),
        
        DefaultRoutineTemplate(
            name: "Household Maintenance",
            description: "Keep your living space clean and organized",
            tasks: [
                DefaultTaskTemplate(name: "Tidy Bedroom", suggestedDuration: 5, suggestedPriority: .core, repetitionIntervalDays: 2),
                DefaultTaskTemplate(name: "Tidy Bathroom", suggestedDuration: 5, suggestedPriority: .nonEssential, repetitionIntervalDays: 4),
                DefaultTaskTemplate(name: "Tidy Kitchen", suggestedDuration: 10, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Clean Sink", suggestedDuration: 3, suggestedPriority: .nonEssential, repetitionIntervalDays: 1),
                DefaultTaskTemplate(name: "Clear Drying Rack", suggestedDuration: 2, suggestedPriority: .nonEssential, repetitionIntervalDays: 1),
                DefaultTaskTemplate(name: "Empty Kitchen Bin", suggestedDuration: 2, suggestedPriority: .nonEssential, repetitionIntervalDays: 3),
                DefaultTaskTemplate(name: "Water Plants", suggestedDuration: 10, suggestedPriority: .core, repetitionIntervalDays: 6),
                DefaultTaskTemplate(name: "Laundry", suggestedDuration: 10, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Empty Dehumidifier", suggestedDuration: 3, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Top Up Humidifier", suggestedDuration: 2, suggestedPriority: .core, repetitionIntervalDays: 1)
            ]
        ),
        
        DefaultRoutineTemplate(
            name: "Mental Wellness",
            description: "Focus on mental health and mindfulness",
            tasks: [
                DefaultTaskTemplate(name: "Meditation 1", suggestedDuration: 5, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Meditation 2", suggestedDuration: 15, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Gratitude Journal", suggestedDuration: 5, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "CBD Oil", suggestedDuration: 2, suggestedPriority: .essential, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Walk", suggestedDuration: 30, suggestedPriority: .core, repetitionIntervalDays: 0),
                DefaultTaskTemplate(name: "Yoga", suggestedDuration: 10, suggestedPriority: .essential, repetitionIntervalDays: 0)
            ]
        )
    ]
}