//
//  RoutineRunnerDetailView.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 24/10/2024.
//

// RoutineRunnerDetailView.swift
import SwiftUI
import CoreData // Import CoreData for preview context

/// RoutineRunnerDetailView provides detailed information about the running routine.
struct RoutineRunnerDetailView: View {
    @ObservedObject var runner: RoutineRunner
    @State private var editMode: EditMode = .active // Enable edit mode for reordering

    // Access managed object context for fetching routine details if needed
    @Environment(\.managedObjectContext) private var viewContext

    // Fetch the full routine details based on the runner's routine property
    // This assumes the runner holds a reference to the CDRoutine
    private var routine: CDRoutine { runner.routine } // Access the routine from runner

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { // Adjusted spacing
            // Display Routine Name
            Text(routine.name ?? "Unnamed Routine")
                .font(.largeTitle)
                .padding(.bottom, 5)

            // Display Schedule Offset
            HStack {
                Text("Schedule Status:")
                    .font(.headline)
                Text(runner.scheduleOffsetString)
                    .font(.headline)
                    .foregroundColor(scheduleColor())
            }

            // Display Current Task Info
            if !runner.isRoutineComplete {
                HStack {
                    Text("Current Task:")
                        .font(.headline)
                    Text("\(runner.currentTaskName) (")
                    + Text(runner.remainingTimeString)
                        .font(.system(.headline, design: .monospaced))
                    + Text(")")
                }
                .foregroundColor(runner.isOverrun ? .red : .primary)
            } else {
                Text("Routine Complete!")
                    .font(.headline)
                    .foregroundColor(.green)
            }

            Divider()

            // Task List with Status
            HStack {
                Text("Tasks (\(runner.currentTaskIndex + 1)/\(runner.scheduledTasks.count))")
                    .font(.headline)
                Spacer()
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 5)

            List {
                ForEach(Array(runner.scheduledTasks.enumerated()), id: \.element.task.objectID) { index, scheduledTask in
                    HStack {
                        Image(systemName: taskStatusIcon(index: index))
                            .foregroundColor(taskStatusColor(index: index))
                            .frame(width: 25, alignment: .center) // Align icons

                        Text(scheduledTask.task.taskName ?? "Unnamed Task")
                            .foregroundColor(index <= runner.currentTaskIndex ? .secondary : .primary) // Dim completed/current tasks

                        Spacer()

                        // Display the ACTUAL allocated duration for this run
                        Text("\(Int(scheduledTask.allocatedDuration / 60)) min")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .deleteDisabled(index <= runner.currentTaskIndex) // Disable delete for completed/current tasks
                    .moveDisabled(index <= runner.currentTaskIndex) // Disable move for completed/current tasks
                }
                .onMove(perform: moveTask)
            }
            .listStyle(PlainListStyle())
            .environment(\.editMode, $editMode) // Apply edit mode

            Spacer()
        }
        .padding()
        .navigationTitle("Routine Progress") // Changed title
        .navigationBarTitleDisplayMode(.inline)
    }

    // Helper to get task status icon
    private func taskStatusIcon(index: Int) -> String {
        if runner.isRoutineComplete || index < runner.currentTaskIndex {
            return "checkmark.circle.fill"
        } else if index == runner.currentTaskIndex {
            return runner.isRunning ? "play.circle.fill" : "pause.circle.fill"
        } else {
            return "circle"
        }
    }

    // Helper to get task status color
    private func taskStatusColor(index: Int) -> Color {
        if runner.isRoutineComplete || index < runner.currentTaskIndex {
            return .green
        } else if index == runner.currentTaskIndex {
            return runner.isRunning ? .blue : .orange
        } else {
            return .gray
        }
    }

    /// Determines the color for the schedule offset string based on the view model's offset value.
    private func scheduleColor() -> Color {
         if runner.scheduleOffsetString == "On schedule" {
             return .secondary // Use gray for on schedule
         } else if runner.scheduleOffsetString.contains("ahead") {
             return .green // Green for ahead
         } else if runner.scheduleOffsetString.contains("behind") {
             return .red // Red for behind
         } else {
             return .primary // Default color if something unexpected happens
         }
     }
     
    // Function to handle reordering tasks
    private func moveTask(from source: IndexSet, to destination: Int) {
        runner.reorderTasks(from: source, to: destination)
    }

}

struct RoutineRunnerDetailView_Previews: PreviewProvider {
    static var previews: some View {
        // --- Create Preview Data ---
        let context = CoreDataStack.shared.viewContext // Use shared view context

        // 1. Create a sample Routine
        let sampleRoutine = CDRoutine(context: context)
        sampleRoutine.uuid = UUID()
        sampleRoutine.name = "Preview Morning Routine"

        // 2. Create sample Tasks
        let task1 = CDTask(context: context)
        task1.uuid = UUID()
        task1.taskName = "Warm-up"
        task1.minDuration = 5
        task1.maxDuration = 5

        let task2 = CDTask(context: context)
        task2.uuid = UUID()
        task2.taskName = "Main Exercise"
        task2.minDuration = 20
        task2.maxDuration = 30

        let task3 = CDTask(context: context)
        task3.uuid = UUID()
        task3.taskName = "Cool Down"
        task3.minDuration = 10
        task3.maxDuration = 15

        // 3. Create RoutineTask links (connecting Tasks to Routine with order)
        let rtLink1 = CDRoutineTask(context: context)
        rtLink1.routine = sampleRoutine
        rtLink1.task = task1
        rtLink1.order = 0

        let rtLink2 = CDRoutineTask(context: context)
        rtLink2.routine = sampleRoutine
        rtLink2.task = task2
        rtLink2.order = 1

        let rtLink3 = CDRoutineTask(context: context)
        rtLink3.routine = sampleRoutine
        rtLink3.task = task3
        rtLink3.order = 2

        // 4. Create a sample schedule ([ScheduledTask])
        //    (Assuming all tasks are scheduled with their minDuration for preview)
        let schedule = [
            ScheduledTask(task: task1, allocatedDuration: TimeInterval(task1.minDuration * 60)),
            ScheduledTask(task: task2, allocatedDuration: TimeInterval(task2.minDuration * 60)),
            ScheduledTask(task: task3, allocatedDuration: TimeInterval(task3.minDuration * 60))
        ]

        // 5. Create the Runner instance using the new initializer
        let runner = RoutineRunner(context: context, routine: sampleRoutine, schedule: schedule)

        // --- Optionally modify runner state for preview ---
        // runner.currentTaskIndex = 1 // Start preview on second task
        // runner.configureTask(at: 1) // Configure for the second task
        // runner.isRunning = true
        // runner.scheduleOffset = -30 // 30 seconds ahead
        // runner.updateScheduleOffsetString()
        // runner.startTimer() // Start the timer visually (won't progress in preview)

        // --- Return the View ---
        return NavigationView {
            RoutineRunnerDetailView(runner: runner)
                .environment(\.managedObjectContext, context)
        }
    }
}

