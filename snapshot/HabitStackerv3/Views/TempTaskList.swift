import Foundation

// Wrapper to make task list identifiable for sheet presentation
struct TempTaskList: Identifiable {
    let id = UUID()
    let tasks: [String]
}