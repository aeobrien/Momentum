import SwiftUI
import OSLog // Import the OSLog framework

struct RoutineRunnerView: View {
    /// The view model containing the timer state and logic.
    @ObservedObject var viewModel: RoutineRunnerViewModel
    /// Logger for UI-specific debug messages.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineRunnerView")

    var body: some View {
        VStack(spacing: 20) { // Adjusted spacing slightly

            // Display Current Task
            Text(viewModel.currentTaskName)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .frame(height: 80) // Give it some fixed height to avoid jumps
                .minimumScaleFactor(0.5) // Allow text to shrink if needed
                .lineLimit(2) // Allow up to two lines for longer names
                .onAppear {
                    logger.debug("RoutineRunnerView appeared.")
                }
                .onDisappear {
                    logger.debug("RoutineRunnerView disappeared.")
                }

            // Display Timer
            Text(viewModel.remainingTimeString)
                .font(.system(size: 80, weight: .bold, design: .monospaced))
                .padding(.vertical, 10) // Adjust padding
                .frame(minWidth: 0, maxWidth: .infinity) // Ensure it takes available width
                .background(Color(.systemGray5)) // Subtle background
                .cornerRadius(15)
                .foregroundColor(viewModel.isOverrun ? .red : .primary) // Show red if overrun

            // Display Schedule Offset
            Text(viewModel.scheduleOffsetString)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(scheduleColor()) // Dynamically color the text
                .padding(.bottom, 10) // Add some space below offset

            // --- Control Buttons ---

            // Start/Pause Row
            HStack(spacing: 20) {
                // Start/Resume Button
                Button {
                    logger.info("Start/Resume button tapped.")
                    viewModel.startTimer()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                // Disable if timer is already running OR if the whole routine is complete
                .disabled(viewModel.isRunning || viewModel.isRoutineComplete)

                // Pause Button
                Button {
                    logger.info("Pause button tapped.")
                    viewModel.pauseTimer()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                // Disable if timer is NOT running OR if the whole routine is complete
                .disabled(!viewModel.isRunning || viewModel.isRoutineComplete)
            }

            // Done Button
            Button {
                 logger.info("Done button tapped.")
                 viewModel.markTaskComplete()
             } label: {
                 Label("Done", systemImage: "checkmark.circle.fill")
                     .padding()
                     .frame(maxWidth: .infinity) // Make button full width
             }
             .buttonStyle(.borderedProminent)
             .tint(.blue) // Use blue for Done
             // Disable if the routine is complete
             .disabled(viewModel.isRoutineComplete)

             // Reset Button (Optional - maybe move or remove depending on final UI)
             Button {
                 logger.info("Reset button tapped.")
                 viewModel.resetTimer()
             } label: {
                 Label("Reset Task Timer", systemImage: "arrow.counterclockwise")
                     .padding()
                     .frame(maxWidth: .infinity)
             }
             .buttonStyle(.bordered) // Less prominent style
             .tint(.red) // Use red for reset
             // Disable if the routine is complete
             .disabled(viewModel.isRoutineComplete)

            Spacer() // Push content to the top
        }
        .padding() // Add padding around the VStack
    }

    /// Determines the color for the schedule offset string based on the view model's offset value.
    /// - Returns: A Color (green for ahead, red for behind, gray for on schedule).
    private func scheduleColor() -> Color {
         // Check scheduleOffsetString directly as it handles the "On schedule" case
         if viewModel.scheduleOffsetString == "On schedule" {
             return .secondary // Use gray for on schedule
         } else if viewModel.scheduleOffsetString.contains("ahead") {
             return .green // Green for ahead
         } else if viewModel.scheduleOffsetString.contains("behind") {
             return .red // Red for behind
         } else {
             return .primary // Default color if something unexpected happens
         }
     }
}

// Preview provider for RoutineRunnerView
struct RoutineRunnerView_Previews: PreviewProvider {
    static var previews: some View {
        // Get the preview context
        let previewContext = PersistenceController.preview.container.viewContext
        // Create a preview instance of the view model using the context
        let previewViewModel = RoutineRunnerViewModel(context: previewContext)

        // Optionally set some state for previewing different scenarios
        // previewViewModel.currentTaskName = "A Very Long Task Name That Might Wrap"
        // previewViewModel.remainingTimeString = "10:30"
        // previewViewModel.scheduleOffsetString = "01:15 behind schedule"
        // previewViewModel.isRunning = false
        // previewViewModel.isRoutineComplete = false
        // previewViewModel.isOverrun = true // Test overrun color

        NavigationView { // Embed in NavigationView for title context
            RoutineRunnerView(viewModel: previewViewModel)
                .navigationTitle("Preview Routine")
                // Also inject the context into the preview environment if needed by subviews (good practice)
                 .environment(\.managedObjectContext, previewContext)
        }
    }
} 