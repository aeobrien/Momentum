import SwiftUI
import CoreData
import OSLog

struct RoutineRunnerView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject var runner: RoutineRunner
    
    // State variables
    @State private var showTaskList: Bool = false
    @State private var showDurationSuggestions: Bool = false
    @State private var showBackgroundTasks: Bool = true
    @State private var infoMode: Bool = false
    @State private var highlightedElement: String? = nil
    @State private var minimalMode: Bool = true
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineRunnerView")
    
    // Helper function for schedule color
    private func scheduleColor() -> Color {
        if runner.scheduleOffsetString.contains("ahead") {
            return Color(red: 0, green: 0.7, blue: 0)
        } else if runner.scheduleOffsetString.contains("behind") {
            return Color(red: 0.8, green: 0, blue: 0)
        } else {
            return .secondary // On schedule
        }
    }
    
    private func scheduleIconName() -> String {
        if runner.scheduleOffsetString == "On schedule" {
            return "checkmark.circle.fill"
        } else if runner.scheduleOffsetString.contains("ahead") {
            return "checkmark.circle.fill"
        } else if runner.scheduleOffsetString.contains("behind") {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private func finalScheduleDifference() -> String {
        let actualFinishTime = Date()
        let timeDifference = actualFinishTime.timeIntervalSince(runner.originalFinishingTime)
        
        if abs(timeDifference) < 1.0 {
            return "On schedule"
        } else {
            let totalSeconds = Int(abs(timeDifference))
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            
            let timeString: String
            if hours > 0 {
                timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                timeString = String(format: "%d:%02d", minutes, seconds)
            }
            
            if timeDifference < 0 {
                return timeString + " ahead of schedule"
            } else {
                return timeString + " behind schedule"
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if !runner.isRoutineComplete {
                ZStack {
                    // Main content
                    VStack(spacing: 20) {
                        // Top bar with X, routine info, and info button
                        if minimalMode {
                            // Minimal mode - just show info button in top-left
                            HStack {
                                Button(action: {
                                    if infoMode {
                                        infoMode = false
                                        highlightedElement = nil
                                    } else {
                                        infoMode = true
                                        highlightedElement = nil
                                    }
                                }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                }
                                Spacer()
                                Button(action: {
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.blue)
                                        .font(.title2)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        } else {
                            // Detailed mode - show full top bar
                            HStack {
                                Button(action: {
                                    if infoMode {
                                        infoMode = false
                                        highlightedElement = nil
                                    } else {
                                        infoMode = true
                                        highlightedElement = nil
                                    }
                                }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                }
                                
                                Spacer()
                                
                                if runner.backgroundTasks.isEmpty {
                                    Text("\(runner.routine.name ?? "Routine") \(runner.currentTaskIndex + 1)/\(runner.scheduledTasks.count)")
                                        .font(.headline)
                                        .onTapGesture { 
                                            if infoMode { 
                                                highlightedElement = "routine" 
                                            } else {
                                                showTaskList = true
                                            }
                                        }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if infoMode {
                                        infoMode = false
                                        highlightedElement = nil
                                    } else {
                                        // Handle exit action
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.blue)
                                        .font(.title2)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }
                        
                        // Current task name
                        Text(runner.currentTaskName)
                            .font(.system(size: minimalMode ? 42 : 34, weight: .bold))
                            .foregroundColor(runner.isOverrun ? .red : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal)
                            .frame(minHeight: 40, maxHeight: minimalMode ? 120 : 100)
                            .padding(.top, minimalMode ? 20 : 0)
                            .onTapGesture { 
                                if infoMode { 
                                    highlightedElement = "title" 
                                } else {
                                    showTaskList = true
                                }
                            }
                        
                        // Next task preview (hide in minimal mode)
                        if !minimalMode {
                            Group {
                                if let nextTaskName = runner.nextTaskName {
                                    Text("Coming Up: \(nextTaskName)")
                                        .font(.system(size: 20))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .padding(.horizontal)
                                } else {
                                    Text("Coming Up: Last task")
                                        .font(.system(size: 20))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onTapGesture { 
                                if infoMode { 
                                    highlightedElement = "comingUp" 
                                } else {
                                    showTaskList = true
                                }
                            }
                        }
                        
                        // Circular progress and timer
                        ZStack {
                            ConcentricProgressView(
                                outerProgress: runner.progressFraction,
                                innerProgress: runner.taskProgressFraction,
                                size: 280,
                                innerProgressColor: runner.isOverrun ? .red : .blue
                            )
                            .onTapGesture { 
                                if infoMode { 
                                    highlightedElement = "progress" 
                                }
                            }
                            
                            // Timer display - tap to pause/play
                            ZStack {
                                Text(runner.remainingTimeString)
                                    .font(.system(size: 64, weight: .light).monospacedDigit())
                                    .foregroundColor(runner.isRunning ? (runner.isOverrun ? .red : .blue) : .gray)
                                
                                // Pause icon overlay when paused
                                if !runner.isRunning && !runner.isRoutineComplete {
                                    Image(systemName: "pause.circle.fill")
                                        .font(.system(size: 140))
                                        .foregroundColor(.black)
                                        .opacity(0.8)
                                }
                            }
                            .onTapGesture { 
                                if infoMode { 
                                    highlightedElement = "timer" 
                                } else {
                                    // Toggle pause/play
                                    if runner.isRunning {
                                        logger.info("Timer tapped - pausing")
                                        runner.pauseTimer()
                                    } else {
                                        logger.info("Timer tapped - resuming")
                                        runner.startTimer()
                                    }
                                }
                            }
                        }
                        .padding(.top, minimalMode ? 60 : 30)
                        
                        // Add flexible spacer in minimal mode to push content down
                        if minimalMode {
                            Spacer()
                        }
                        
                        // Schedule status with spend time button (hide in minimal mode)
                        if !minimalMode {
                            Button(action: {
                                if infoMode {
                                    highlightedElement = "schedule"
                                } else if runner.canSpendTime {
                                    runner.showSpendTimeSheet = true
                                }
                            }) {
                                HStack(spacing: 8) {
                                    VStack(spacing: 4) {
                                        HStack(spacing: 8) {
                                            Image(systemName: scheduleIconName())
                                                .foregroundColor(Color(red: 0, green: 0.7, blue: 0))
                                            
                                            Text(runner.scheduleOffsetString)
                                                .foregroundColor(Color(red: 0, green: 0.7, blue: 0))
                                                .font(.body)
                                                .fontWeight(.bold)
                                            
                                            if runner.canSpendTime && runner.scheduleOffsetString.contains("ahead") {
                                                Image(systemName: "bitcoinsign.circle.fill")
                                                    .foregroundColor(.yellow)
                                                    .font(.body)
                                            }
                                        }
                                        
                                        Text(runner.estimatedFinishingTimeString)
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!runner.canSpendTime && !infoMode)
                            .padding(.top, 10)
                        }
                        
                        Spacer()
                        
                        // Add flexible spacer in minimal mode to push buttons up
                        if minimalMode {
                            Spacer()
                        }
                        
                        // Action buttons
                        if !minimalMode {
                            HStack(spacing: 40) {
                                // Interruption - far left
                                Button(action: {
                                    if infoMode {
                                        highlightedElement = "interrupt"
                                    } else {
                                        logger.info("Interruption button tapped.")
                                        runner.handleInterruption()
                                    }
                                }) {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                }
                                .disabled((runner.isRoutineComplete || runner.isHandlingInterruption) && !infoMode)
                                
                                // Delay (hourglass) - second from left
                                Button(action: {
                                    if infoMode {
                                        highlightedElement = "delay"
                                    } else {
                                        logger.info("Delay button tapped.")
                                        runner.delayCurrentTask()
                                    }
                                }) {
                                    Image(systemName: "hourglass")
                                        .foregroundColor(.purple)
                                        .font(.title2)
                                }
                                .disabled((runner.isRoutineComplete || !runner.canDelayCurrentTask) && !infoMode)
                                
                                // Toggle minimal mode (minus) - center
                                Button(action: {
                                    if infoMode {
                                        highlightedElement = "minimal"
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            minimalMode.toggle()
                                        }
                                    }
                                }) {
                                    Image(systemName: "minus")
                                        .foregroundColor(.gray)
                                        .font(.title2)
                                }
                                
                                // Skip - second from right
                                Button(action: {
                                    if infoMode {
                                        highlightedElement = "skip"
                                    } else {
                                        logger.info("Skip button tapped.")
                                        runner.skipCurrentTask()
                                    }
                                }) {
                                    Image(systemName: "forward.fill")
                                        .foregroundColor(.yellow)
                                        .font(.title2)
                                }
                                .disabled(runner.isRoutineComplete && !infoMode)
                                
                                // Continue in Background - far right
                                Button(action: {
                                    if infoMode {
                                        highlightedElement = "background"
                                    } else if runner.canMoveToBackground {
                                        logger.info("Continue in Background button tapped.")
                                        withAnimation {
                                            runner.moveCurrentTaskToBackground()
                                        }
                                    }
                                }) {
                                    Image(systemName: "arrow.uturn.down")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                }
                                .disabled(!runner.canMoveToBackground && !infoMode)
                            }
                            .padding(.vertical, 20)
                        } else {
                            // Minimal mode - show hourglass, plus, skip buttons
                            HStack(spacing: 40) {
                                // Delay (hourglass) - left
                                Button(action: {
                                    logger.info("Delay button tapped in minimal mode.")
                                    runner.delayCurrentTask()
                                }) {
                                    Image(systemName: "hourglass")
                                        .foregroundColor(.purple)
                                        .font(.title2)
                                }
                                .disabled(runner.isRoutineComplete || !runner.canDelayCurrentTask)
                                
                                // Expand to full view (plus) - center
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        minimalMode = false
                                    }
                                }) {
                                    Image(systemName: "plus")
                                        .foregroundColor(.gray)
                                        .font(.title2)
                                }
                                
                                // Skip - right
                                Button(action: {
                                    logger.info("Skip button tapped in minimal mode.")
                                    runner.skipCurrentTask()
                                }) {
                                    Image(systemName: "forward.fill")
                                        .foregroundColor(.yellow)
                                        .font(.title2)
                                }
                                .disabled(runner.isRoutineComplete)
                            }
                            .padding(.vertical, 20)
                        }
                        
                        // Slide to complete
                        ZStack {
                            SlideToCompleteView {
                                logger.info("Task completed via slide.")
                                runner.markTaskComplete()
                            }
                            .disabled(runner.isRoutineComplete)
                            .padding(.horizontal)
                            .onTapGesture {
                                if infoMode {
                                    highlightedElement = "complete"
                                }
                            }
                        }
                        
                        // Bottom spacing
                        Spacer().frame(height: 20)
                    }
                    .saturation(infoMode ? 0 : 1)
                    .background(Color(.systemGray6))
                    .onAppear {
                        // Start the timer automatically when view appears
                        if !runner.isRunning && !runner.isRoutineComplete && runner.currentTaskIndex >= 0 {
                            runner.startTimer()
                        }
                    }
                    
                    // Background tasks overlay - at top
                    if showBackgroundTasks && !runner.backgroundTasks.isEmpty {
                        VStack {
                            BackgroundTasksBar(runner: runner)
                                .padding(.top, 14)
                            Spacer()
                        }
                    }
                    
                    // Info mode overlay
                    if infoMode && highlightedElement == nil {
                        VStack {
                            Spacer()
                            Text("Tap anywhere for more information")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(12)
                                .padding(.bottom, 80)
                        }
                    }
                    
                    // Info text overlay
                    if let element = highlightedElement {
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                let position = infoPosition(for: element, in: geometry.size)
                                let isAboveCenter = position.y < geometry.size.height / 2
                                
                                if !isAboveCenter {
                                    Spacer()
                                }
                                
                                Text(infoText(for: element))
                                    .foregroundColor(.white)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .padding(12)
                                    .background(Color.black.opacity(0.85))
                                    .cornerRadius(12)
                                    .frame(maxWidth: min(geometry.size.width * 0.85, 300))
                                    .padding(.horizontal)
                                    .padding(.vertical, getVerticalPadding(for: element, in: geometry.size))
                                
                                if isAboveCenter {
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .sheet(isPresented: $showTaskList) {
                    RoutineRunnerDetailView(
                        runner: runner
                    )
                }
                .sheet(isPresented: $runner.showSpendTimeSheet) {
                    SpendOverUnderView(runner: runner)
                }
                .onChange(of: scenePhase) { newPhase in
                    logger.debug("Scene phase changed to: \\(String(describing: newPhase))")
                    switch newPhase {
                    case .active:
                        runner.observeScenePhase(.active)
                    case .inactive:
                        runner.observeScenePhase(.inactive)
                    case .background:
                        runner.observeScenePhase(.background)
                    @unknown default:
                        break
                    }
                }
                .onAppear {
                    // Remove duration suggestions handling for now
                }
            } else {
                // Routine complete view
                VStack(spacing: 30) {
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    
                    Text("Routine Complete!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Display original vs actual finish times
                    VStack(spacing: 10) {
                        HStack {
                            Text("Original estimated finish:")
                                .foregroundColor(.secondary)
                            Text(DateFormatter.localizedString(from: runner.originalFinishingTime, dateStyle: .none, timeStyle: .short))
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 18))
                        
                        HStack {
                            Text("Actual finish time:")
                                .foregroundColor(.secondary)
                            Text(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 18))
                        
                        if runner.scheduleOffsetString != "On schedule" {
                            Text("(" + finalScheduleDifference().lowercased() + ")")
                                .font(.subheadline)
                                .foregroundColor(scheduleColor())
                                .padding(.top, 5)
                        }
                    }
                    .padding(.vertical, 10)
                    
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.headline)
                    .padding()
                    .frame(width: 200)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            // Stop the routine and clean up all timers when view disappears
            runner.stopRoutine()
            logger.info("RoutineRunnerView disappeared - stopped routine and cleaned up timers")
        }
    }
    
    // Info mode helper functions
    func infoText(for element: String) -> String {
        switch element {
        case "routine": return "Shows the routine name and current task number."
        case "title": return "Name of the current task. Tap to view all tasks."
        case "comingUp": return "Name of the next task. Tap to view all tasks."
        case "timer": return "Time remaining for current task. Tap to pause/resume."
        case "progress": return "Outer ring: overall routine progress. Inner ring: current task progress."
        case "schedule": return "Shows if you're ahead/behind schedule. Tap to spend extra time when ahead."
        case "skip": return "Skip the current task and move to the next one."
        case "delay": return "Move this task later in the routine."
        case "minimal": return "Switch to minimal view for less distraction."
        case "interrupt": return "Add a 3-minute interruption task."
        case "background": return "Continue this task in the background while starting the next one."
        case "complete": return "Slide to mark the current task as completed."
        default: return ""
        }
    }
    
    func infoPosition(for element: String, in size: CGSize) -> CGPoint {
        switch element {
        case "routine": return CGPoint(x: size.width / 2, y: 70)
        case "title": return CGPoint(x: size.width / 2, y: 130)
        case "comingUp": return CGPoint(x: size.width / 2, y: 190)
        case "progress": return CGPoint(x: size.width / 2, y: 380)
        case "timer": return CGPoint(x: size.width / 2, y: 380)
        case "schedule": return CGPoint(x: size.width / 2, y: 520)
        case "interrupt", "delay", "minimal", "skip", "background": 
            return CGPoint(x: size.width / 2, y: size.height - 200)
        case "complete": return CGPoint(x: size.width / 2, y: size.height - 120)
        default: return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }
    
    func getVerticalPadding(for element: String, in size: CGSize) -> CGFloat {
        switch element {
        case "routine": return 120
        case "title": return 180
        case "comingUp": return 240
        case "progress", "timer": return 60
        case "schedule": return 100
        case "interrupt", "delay", "minimal", "skip", "background": return 60
        case "complete": return 40
        default: return 60
        }
    }
}
