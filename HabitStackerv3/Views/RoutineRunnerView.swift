import SwiftUI
import CoreData
import OSLog

// MARK: - Progress Bar Helper View
struct ProgressBarView: View {
    let value: Double // 0.0 to 1.0
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar
            ProgressView(value: value)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue)) // Or choose your preferred color
                .scaleEffect(x: 1, y: 1.5, anchor: .center) // Slightly thicker bar

            // Label below the bar (e.g., "Task 5 / 12")
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center) // Center the label text
        }
        .padding(.bottom, 10) // Add some spacing below the progress bar group
    }
}

struct RoutineRunnerView: View {
    // @Environment(\.managedObjectContext) private var viewContext // Context comes from runner
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var runner: RoutineRunner
    // Add state for UI toggle and sheet presentation
    @State private var detailsVisible: Bool = false
    @State private var showTaskList: Bool = false
    @State private var showDurationSuggestions: Bool = false
    @Namespace private var animation // Add namespace for matched geometry effect

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineRunnerView")

    // Keep existing helper function for color
    private func scheduleColor() -> Color {
        if runner.scheduleOffsetString == "On schedule" {
            return .secondary // Use a less prominent color for "on schedule"
        } else if runner.scheduleOffsetString.contains("ahead") {
            return .green
        } else if runner.scheduleOffsetString.contains("behind") {
            return .red
        } else {
            return .primary // Default color
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Use the runner's completion state to switch views
            if !runner.isRoutineComplete {
                // Main Running View
                VStack(spacing: 0) {
                    // Content area that adapts based on detailsVisible
                    ZStack {
                        VStack(spacing: 0) {
                            // --- Top Spacer --- 
                            // Only use Spacer in simple view for centering
                            if !detailsVisible {
                                Spacer() // Pushes content towards the center vertically
                            }

                            // --- Timer Display ---
                            Text(runner.remainingTimeString)
                                .font(.system(size: 24, weight: .bold, design: .rounded)) // Old simple view size
                                .foregroundColor(runner.isOverrun ? .red : .primary)
                                .frame(height: 40) // Fixed height like old simple view
                                .padding(.bottom, 10) // Add small consistent padding
                                .matchedGeometryEffect(id: "timer", in: animation) // Animation for timer
                                // Conditionally offset timer UP in simple view
                                .offset(y: detailsVisible ? 0 : -50)

                            // --- Task Name Display ---
                            Text(runner.currentTaskName) // Use current task name from runner
                                .font(.system(size: 46, weight: .bold, design: .rounded)) // Old styling
                                .lineLimit(3) // Allow multiple lines
                                .multilineTextAlignment(.center)
                                .foregroundColor(runner.isOverrun ? .red : .primary) // Change color if overrun
                                .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(Color(.secondarySystemBackground)) // Use system background color
                                        .shadow(radius: 3)
                                        // Ensure background adapts to screen width with padding
                                        .frame(width: geometry.size.width - 40)
                                )
                                .padding(.horizontal, 20) // Outer padding for the background
                                .matchedGeometryEffect(id: "taskName", in: animation) // Animation for task name
                                .zIndex(1) // Ensure Task Name is drawn on top during animation
                                .onTapGesture {
                                    // Toggle details visibility with animation
                                    withAnimation(.easeInOut(duration: 0.4)) { // Slightly longer duration for glide
                                        detailsVisible.toggle()
                                    }
                                    logger.debug("Toggled detailsVisible to \\(self.detailsVisible)")
                                }

                            // --- Progress Bar (MOVED HERE - Below Task Name, Always Visible) ---
                            ProgressBarView(
                                value: runner.progressFraction,
                                label: runner.progressTaskString
                            )
                            .frame(width: geometry.size.width - 80) // Match width of task name tile padding
                            .padding(.top, 50) // INCREASED Space between task name and progress bar (was 15)
                            // No opacity/offset needed as it's always visible relative to task name
                            // Conditionally offset progress bar DOWN in simple view
                            .offset(y: detailsVisible ? 0 : 30)
                            
                            // --- Task Progress Bar ---
                            TaskProgressBarView(
                                value: runner.taskProgressFraction,
                                label: "Task Progress"
                            )
                            .frame(width: geometry.size.width - 80)
                            .padding(.top, 5)
                            .offset(y: detailsVisible ? 0 : 30)

                            // --- Conditional Detailed View Content Group (Status, Next Task, Buttons) ---
                            // Order and transitions adjusted
                            if detailsVisible {
                                // Space below progress bar - Remains static
                                Spacer().frame(height: 20)

                                // --- Status Section (Using runner's schedule offset) ---
                                VStack(spacing: 12) {
                                    HStack {
                                        Image(systemName: scheduleIconName())
                                            .foregroundColor(scheduleColor())
                                        Text(runner.scheduleOffsetString)
                                            .font(.headline)
                                            .foregroundColor(scheduleColor())
                                    }
                                    
                                    // Estimated finishing time
                                    Text(runner.estimatedFinishingTimeString)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(height: 90)
                                .frame(maxWidth: .infinity)
                                // Updated transition offset based on new layout
                                .transition(.opacity.combined(with: .offset(y: -20)))

                                // --- Next Task Preview (MOVED UP) ---
                                // Spacer remains static
                                Spacer().frame(height: 10) // DECREASED Space between status and next task (was 15)

                                VStack(spacing: 8) {
                                    if let nextTaskName = runner.nextTaskName, !runner.isRoutineComplete {
                                        Text("Coming up:")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        Text(nextTaskName)
                                            .font(.system(size: 22, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .padding(.horizontal)
                                        // Optional: Display duration if available
                                        /*
                                        if let nextTaskDuration = runner.nextTaskDurationString, !nextTaskDuration.isEmpty {
                                            Text(nextTaskDuration)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        */
                                    } else if !runner.isRoutineComplete {
                                        Text("Last task in routine")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(height: 80) // Keep fixed height
                                .frame(maxWidth: .infinity)
                                // Updated transition offset for Next Task Preview
                                .transition(.opacity.combined(with: .offset(y: -50))) // Was -80

                                // --- Action Buttons (MOVED DOWN) ---
                                // Spacer remains static
                                Spacer().frame(height: 15)

                                HStack(spacing: 40) {
                                    // Skip Button
                                    Button {
                                        logger.info("Skip button tapped.")
                                        runner.skipCurrentTask()
                                    } label: {
                                        VStack {
                                            Image(systemName: "forward.fill").font(.title)
                                            Text("Skip").font(.caption)
                                        }.foregroundColor(.yellow)
                                    }.disabled(runner.isRoutineComplete)

                                    // Delay Button
                                    Button {
                                        logger.info("Delay button tapped.")
                                        runner.delayCurrentTask()
                                    } label: {
                                        VStack {
                                            Image(systemName: "hourglass").font(.title)
                                            Text("Delay").font(.caption)
                                        }.foregroundColor(.orange)
                                    }.disabled(runner.isRoutineComplete || !runner.canDelayCurrentTask)

                                    // Pause/Resume Button
                                    Button {
                                        if runner.isRunning {
                                            logger.info("Pause button tapped.")
                                            runner.pauseTimer()
                                        } else {
                                            logger.info("Resume button tapped.")
                                            runner.startTimer()
                                        }
                                    } label: {
                                        VStack {
                                            Image(systemName: runner.isRunning ? "pause.fill" : "play.fill").font(.title)
                                            Text(runner.isRunning ? "Pause" : "Resume").font(.caption)
                                        }.foregroundColor(.blue)
                                    }.disabled(runner.isRoutineComplete)

                                    // Tasks Button
                                    Button {
                                        logger.debug("Tasks button tapped.")
                                        showTaskList.toggle()
                                    } label: {
                                        VStack {
                                            Image(systemName: "list.bullet").font(.title)
                                            Text("Tasks").font(.caption)
                                        }.foregroundColor(.blue)
                                    }
                                }
                                .frame(height: 60) // Fixed height
                                .frame(maxWidth: .infinity)
                                // Updated transition offset for Action Buttons
                                .transition(.opacity.combined(with: .offset(y: -80))) // Was -50

                                // Spacer remains static
                                Spacer().frame(height: 10)
                            }

                            // --- Spacer for Simple View ---
                            // Keep the bottom spacer for centering in simple view
                            if !detailsVisible {
                                Spacer(minLength: 0) // Pushes content towards the center vertically in simple view
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // Make VStack fill the ZStack
                    }
                    .frame(maxHeight: .infinity) // Allow ZStack to take available vertical space

                    // --- Fixed Bottom Section (Slide to Complete) ---
                    VStack(spacing: 0) {
                        // Divider line
                        Divider()
//                        Color(.systemGray5) // Alternative divider style
//                            .frame(height: 1)
//                            .shadow(radius: 1)

                        // Slide to complete view
                        SlideToCompleteView {
                            logger.info("Slide to complete activated.")
                            runner.markTaskComplete() // Action triggers task completion in runner
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12) // Padding like old UI
                        .background(Color(.systemBackground)) // Match system background
                    }
                    .frame(height: 80) // Give fixed height to the bottom bar area
                }
                // --- Move Toolbar here --- 
                .toolbar { // Add custom back/cancel button if needed
                    ToolbarItem(placement: .navigationBarLeading) {
                        if !runner.isRoutineComplete { // Only show if routine is running
                            Button {
                                logger.warning("User tapped custom back button - cancelling routine.")
                                // Stop the routine properly before dismissing
                                runner.stopRoutine()
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                Image(systemName: "xmark") // Use 'xmark' for cancel/close
                            }
                        }
                    }
                }
            } else {
                // --- Completion View ---
                VStack {
                    Spacer() // Push content to center
                    Text("Routine Complete! 🎉")
                        .font(.largeTitle)
                        .padding()

                    Spacer().frame(height: 20) // Space before suggestions
                    
                    // Show duration suggestions if any
                    if !runner.durationSuggestions.isEmpty {
                        Button {
                            showDurationSuggestions = true
                        } label: {
                            Label("View Duration Suggestions (\(runner.durationSuggestions.count))", systemImage: "clock.arrow.2.circlepath")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }

                    Spacer().frame(height: 20) // Space before button

                    Button {
                        logger.info("Return to Schedule button tapped.")
                        // Dismiss the view using presentationMode
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Return to Schedule")
                            .font(.title2)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue) // Style like old UI
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                    .padding() // Padding around the button

                    Spacer() // Push content to center
                }
                // --- Completion View should also have Navigation Title --- 
                .navigationTitle(runner.routine.name ?? "Routine") // Ensure title persists
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true) // Still hide default back
            }
        }
        .navigationTitle(runner.routine.name ?? "Routine") // Use routine name from runner
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Hide default back button
        .onAppear {
            logger.debug("RoutineRunnerView appeared. Attempting to start timer if not already running.")
            if !runner.isRunning && !runner.isRoutineComplete {
                runner.startTimer()
            }
        }
        .onDisappear {
             logger.debug("RoutineRunnerView disappeared.")
             // Optional: Call pause or cleanup method on runner if needed on disappear
             // runner.pauseTimer() // Example: Pause timer if view disappears unexpectedly
        }
        .sheet(isPresented: $showTaskList) {
            NavigationView {
                // CRITICAL: Ensure the correct 'runner' instance is passed
                RoutineRunnerDetailView(runner: runner)
            }
        }
        .sheet(isPresented: $showDurationSuggestions) {
            TaskDurationSuggestionsView(suggestions: runner.durationSuggestions)
                .environment(\.managedObjectContext, runner.context)
        }
        .onChange(of: scenePhase) { newPhase in
            logger.info("Scene phase changed to: \\(String(describing: newPhase))")
            // Assuming runner has this method from previous context
            // If not, this needs to be added to RoutineRunner or removed
             runner.observeScenePhase(newPhase)
        }
    }

    // Helper to get icon name based on schedule status
    private func scheduleIconName() -> String {
        if runner.scheduleOffsetString == "On schedule" {
            return "checkmark.circle.fill"
        } else if runner.scheduleOffsetString.contains("ahead") {
            return "arrow.up.circle.fill" // Old UI used this for ahead
        } else if runner.scheduleOffsetString.contains("behind") {
            return "arrow.down.circle.fill" // Old UI used this for behind
        } else {
            return "questionmark.circle.fill" // Default icon
        }
    }
}

// MARK: - TaskListSheet (Adapted from old version)
// This struct displays the list of tasks in the current routine.
struct TaskListSheet: View {
    @ObservedObject var runner: RoutineRunner
    @Environment(\.presentationMode) var presentationMode
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TaskListSheet")

    // Fix the task retrieval logic
    private var sortedTasks: [CDTask] {
        let routine = runner.routine
        guard let relations = routine.taskRelations?.allObjects as? [CDRoutineTask] else {
            logger.error("Could not fetch routine relations for TaskListSheet")
            return []
        }
        
        let sortedRelations = relations.sorted { $0.order < $1.order }
        return sortedRelations.compactMap { $0.task }
    }

    var body: some View {
        VStack {
            // Header
            HStack {
                Text("Task Progress").font(.headline)
                Spacer()
                Button("Done") { presentationMode.wrappedValue.dismiss() }
            }.padding()

            // Task list
            ScrollView {
                // Fix: Use indices to iterate through the tasks
                ForEach(Array(sortedTasks.indices), id: \.self) { index in
                    let cdTask = sortedTasks[index]
                    HStack {
                        Text(cdTask.taskName ?? "Unnamed Task")
                        Spacer()
                        
                        // Fix: Use index-based comparison instead of non-existent properties
                        if index == runner.currentTaskIndex {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.blue)
                        } else if index < runner.currentTaskIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    Divider()
                }
            }
        }
    }
}


// Preview provider needs adjustment to reflect new structure and dependencies
struct RoutineRunnerView_Previews: PreviewProvider {
    static var previews: some View {
        // --- Create Preview Data ---
        let context = CoreDataStack.shared.viewContext
        let sampleRoutine = CDRoutine(context: context)
        sampleRoutine.uuid = UUID()
        sampleRoutine.name = "Preview Morning Routine"

        let task1 = CDTask(context: context)
        task1.uuid = UUID()
        task1.taskName = "Warm-up: A quick jog around the block to get the blood flowing"
        task1.minDuration = 5
        task1.maxDuration = 5
        task1.essentiality = 3 // Essential

        let task2 = CDTask(context: context)
        task2.uuid = UUID()
        task2.taskName = "Main Exercise: High-Intensity Interval Training (HIIT)"
        task2.minDuration = 20
        task2.maxDuration = 30
        task2.essentiality = 2 // Core

        let task3 = CDTask(context: context)
        task3.uuid = UUID()
        task3.taskName = "Cool Down: Stretching and Foam Rolling"
        task3.minDuration = 10
        task3.maxDuration = 15
        task3.essentiality = 1 // Optional

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
        let sampleSchedule = [
            ScheduledTask(task: task1, allocatedDuration: TimeInterval(task1.minDuration * 60)),
            ScheduledTask(task: task2, allocatedDuration: TimeInterval(task2.minDuration * 60)),
            ScheduledTask(task: task3, allocatedDuration: TimeInterval(task3.minDuration * 60))
        ]

        // 5. Create Runner instances using the new initializer
        let runner = RoutineRunner(context: context, routine: sampleRoutine, schedule: sampleSchedule, originalFinishingTime: Date().addingTimeInterval(3600))
        let simpleRunner = RoutineRunner(context: context, routine: sampleRoutine, schedule: sampleSchedule, originalFinishingTime: Date().addingTimeInterval(3600))
        let completedRunner = RoutineRunner(context: context, routine: sampleRoutine, schedule: sampleSchedule, originalFinishingTime: Date().addingTimeInterval(3600))
        // Simulate completion if needed (Requires changes in RoutineRunner to expose state or method)
        // completedRunner.isRoutineComplete = true // Example - If property is mutable

        // --- Return the View --- Wrap previews in a Group
        return Group {
            // Embed in NavigationView for title and toolbar context
            NavigationView {
                RoutineRunnerView(runner: runner)
                     .environment(\.managedObjectContext, context)
             }
             .previewDisplayName("Detailed View")

            // Preview for Simple View (Set detailsVisible to false)
            NavigationView {
                 // Initialize without detailsVisible - View manages its own state
                RoutineRunnerView(runner: simpleRunner)
                     .environment(\.managedObjectContext, context)
            }
            .previewDisplayName("Simple View")

             // Preview for Completed State
             NavigationView {
                 RoutineRunnerView(runner: completedRunner)
                     .environment(\.managedObjectContext, context)
             }
             .previewDisplayName("Completion View")
        }
    }
}

// --- Add DurationInfo struct if it's not defined elsewhere ---
// This struct was used in RoutineSelectionView, ensure it's available if needed
// or remove if functionality is self-contained.
// struct DurationInfo {
//     let essential: Int
//     let coreAndEssential: Int
//     let all: Int
// }

// --- Add DurationOptionButton struct if it's not defined elsewhere ---
// This was used in RoutineSelectionView. Define it here or ensure it's accessible.
// struct DurationOptionButton: View {
//     let title: String
//     let duration: String
//     let color: Color
//     let isSelected: Bool
//     let action: () -> Void
//
//     var body: some View {
//         Button(action: action) {
//             HStack {
//                 VStack(alignment: .leading) {
//                     Text(title).font(.body).fontWeight(.medium)
//                     Text(duration).font(.caption).foregroundColor(.secondary)
//                 }
//                 Spacer()
//                 if isSelected {
//                     Image(systemName: "checkmark.circle.fill")
//                         .foregroundColor(color)
//                 } else {
//                     Image(systemName: "circle")
//                         .foregroundColor(.gray)
//                 }
//             }
//             .padding()
//             .background(isSelected ? color.opacity(0.1) : Color(.systemGray6))
//             .cornerRadius(8)
//             .overlay(
//                 RoundedRectangle(cornerRadius: 8)
//                     .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
//             )
//         }
//         .buttonStyle(PlainButtonStyle()) // Use PlainButtonStyle to avoid default button styling interference
//     }
// }



// // Ensure CoreDataStack is accessible for previews
// // Uncommented for preview compilation
// class CoreDataStack {
//     static let shared = CoreDataStack()
//     let persistentContainer: NSPersistentContainer
//
//     // Added logger for CoreDataStack initialization
//     private static let logger = Logger(subsystem: // Bundle.main.bundleIdentifier ?? "com.yourapp", category: // "CoreDataStack")
//
//     private init() {
//         persistentContainer = NSPersistentContainer(name: // "HabitStacker") // Replace with your model name
//         // Load synchronously for preview simplicity, add error // handling for production
//         persistentContainer.loadPersistentStores { // (storeDescription, error) in
//             if let error = error as NSError? {
//                  // Use logger instead of fatalError in reusable // component
//                  Self.logger.critical("Unresolved error loading Core // Data persistent store: \\(error), // \\(error.userInfo)")
//                  // Consider how to handle this failure in a real // app (e.g., UI message, fallback)
//                  // fatalError("Unresolved error \\(error), // \\(error.userInfo)") // Avoid fatalError in // production init
//             } else {
//                 Self.logger.info("Core Data store loaded // successfully: // \\(storeDescription.url?.absoluteString ?? // "No URL")")
//             }
//         }
//         // Optional: Set merge policy
//         persistentContainer.viewContext// .automaticallyMergesChangesFromParent = true
//         persistentContainer.viewContext.mergePolicy = // NSMergeByPropertyObjectTrumpMergePolicy
//     }
//
//     var viewContext: NSManagedObjectContext {
//         return persistentContainer.viewContext
//     }
//
//     // Optional: Add a save context helper
//     func saveContext() {
//         let context = viewContext
//         if context.hasChanges {
//             do {
//                 try context.save()
//                 Self.logger.debug("Core Data context saved // successfully.")
//             } catch {
//                 let nserror = error as NSError
//                 Self.logger.error("Unresolved error saving Core Data // context: \\(nserror), \\(nserror.userInfo)")
//                 // Handle save errors appropriately in production
//                 // fatalError("Unresolved error \\(nserror), // \\(nserror.userInfo)")
//             }
//         }
//     }
// }
//
