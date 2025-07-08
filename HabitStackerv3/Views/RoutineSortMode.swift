import Foundation

enum RoutineSortMode: String, CaseIterable {
    case nameAsc = "A to Z"
    case nameDesc = "Z to A"
    case mostTasks = "Most Tasks"
    case fewestTasks = "Fewest Tasks"
    case longestFirst = "Longest First"
    case shortestFirst = "Shortest First"
    case newestFirst = "Most Recently Used"
    case oldestFirst = "Least Recently Used"
}