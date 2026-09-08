// SharedTaskManager.swift

import SwiftUI

class SharedTaskManager: ObservableObject {
    @Published var tasks: [TaskInstance] = []
    @Published var totalTime: TimeInterval = 0
    @Published var expectedEndTime: Date?
    @Published var overUnderTime: TimeInterval = 0

    let jsonFileName = "FullTaskListv2.json"

    init() {
        // Copy the JSON file from the bundle to the Documents directory if needed
        copyJSONToDocumentsDirectoryIfNeeded()
    }

    func calculateTotalTime() {
        totalTime = tasks.reduce(0.0) { $0 + TimeInterval($1.task.minDuration) }
    }

    func calculateExpectedEndTime(from startTime: Date) {
        // Calculate the total time for all tasks
        calculateTotalTime()
        
        // Apply the over/under time to the total time
        let adjustedTime = totalTime - overUnderTime
        
        // Calculate the expected end time based on the start time and the adjusted total time
        expectedEndTime = Calendar.current.date(byAdding: .second, value: Int(adjustedTime), to: startTime)
    }


    func startTaskTimer(for taskInstance: TaskInstance, startTime: Date) {
        if let index = tasks.firstIndex(where: { $0.task.UUID == taskInstance.task.UUID }) {
            tasks[index].startTime = startTime
            tasks[index].expectedEndTime = Calendar.current.date(byAdding: .second, value: tasks[index].task.minDuration, to: startTime)
        }
    }

    func taskCompleted(taskInstance: TaskInstance, actualCompletionTime: Date) {
        if let index = tasks.firstIndex(where: { $0.task.UUID == taskInstance.task.UUID }) {
            let actualDuration = actualCompletionTime.timeIntervalSince(tasks[index].startTime ?? actualCompletionTime)
            let plannedDuration = TimeInterval(tasks[index].task.minDuration)

            let timeDifference = plannedDuration - actualDuration
            
            // Adjust the overUnderTime based on the time difference
            overUnderTime += timeDifference
            
            tasks[index].isCompleted = true

            // Update lastCompleted in the JSON
            updateLastCompletedDate(for: tasks[index].task)
        }
    }

    func updateOverUnderTime(for taskInstance: TaskInstance, currentTime: Date) {
        if let index = tasks.firstIndex(where: { $0.task.UUID == taskInstance.task.UUID }) {
            guard let startTime = tasks[index].startTime else { return }
            let elapsedTime = currentTime.timeIntervalSince(startTime)
            if elapsedTime > TimeInterval(tasks[index].task.minDuration) {
                let overTime = elapsedTime - TimeInterval(tasks[index].task.minDuration)
                overUnderTime -= overTime
            }
        }
    }

    func documentDirectoryPath() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    func bundlePath() -> URL? {
        return Bundle.main.url(forResource: "FullTaskListv2", withExtension: "json")
    }

    func copyJSONToDocumentsDirectoryIfNeeded() {
        let fileManager = FileManager.default
        let fileURL = documentDirectoryPath().appendingPathComponent(jsonFileName)
        let bundleURL = bundlePath()

        guard let bundleURL = bundleURL else {
            print("Error: JSON file not found in the bundle.")
            return
        }

        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.copyItem(at: bundleURL, to: fileURL)
                print("Successfully copied JSON file to Documents directory.")
            } catch {
                print("Failed to copy JSON file to Documents directory: \(error)")
            }
        }
    }

    func loadJSONFromDocumentsDirectory() -> [CustomTask]? {
        let fileURL = documentDirectoryPath().appendingPathComponent(jsonFileName)
        do {
            let data = try Data(contentsOf: fileURL)
            let tasks = try JSONDecoder().decode([CustomTask].self, from: data)
            return tasks
        } catch {
            print("Failed to load tasks from JSON: \(error)")
            return nil
        }
    }

    func saveJSONToDocumentsDirectory(_ tasks: [CustomTask]) {
        let fileURL = documentDirectoryPath().appendingPathComponent(jsonFileName)
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL)
            print("Successfully saved updated tasks to JSON.")
        } catch {
            print("Failed to save tasks to JSON: \(error)")
        }
    }

    func updateLastCompletedDate(for task: CustomTask) {
        let currentDate = ISO8601DateFormatter().string(from: Date())

        // Load the current tasks from the JSON
        guard var loadedTasks = loadJSONFromDocumentsDirectory() else { return }

        // Find the task in the loaded tasks
        if let index = loadedTasks.firstIndex(where: { $0.UUID == task.UUID }) {
            print("Original lastCompleted value: \(loadedTasks[index].lastCompleted ?? "N/A")")

            // Update the lastCompleted date
            loadedTasks[index].lastCompleted = currentDate

            // Save the updated tasks back to the JSON file
            saveJSONToDocumentsDirectory(loadedTasks)

            print("Updated lastCompleted value: \(loadedTasks[index].lastCompleted ?? "N/A")")
        }
    }
}
