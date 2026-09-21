import SwiftUI
import CoreData
import OSLog

struct RoutineRunnerView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) private var viewContext

    @ObservedObject var runner: RoutineRunner
    @StateObject private var settingsManager = SettingsManager.shared

    // State variables
    @State private var showTaskList: Bool = false
    @State private var showDurationSuggestions: Bool = false
    @State private var showBackgroundTasks: Bool = true
    @State private var selectedThreshold: Double = 0.3
    @State private var infoMode: Bool = false
    @State private var highlightedElement: String? = nil
    @State private var minimalMode: Bool = true
    @State private var taskToEdit: RoutineRunner.TaskCompletionAnalytics? = nil
    @State private var showEditDurationSheet: Bool = false
    @State private var cdTaskToEdit: CDTask? = nil
    @State private var showTaskEditSheet: Bool = false
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "RoutineRunnerView")
    
    // Computed property to get current task
    private var currentTask: CDTask? {
        guard runner.currentTaskIndex >= 0 && runner.currentTaskIndex < runner.scheduledTasks.count else {
            return nil
        }
        return runner.scheduledTasks[runner.currentTaskIndex].task
    }
    
    // Check if current task is a checklist task
    private var isChecklistTask: Bool {
        let isChecklist = currentTask?.isChecklistTask ?? false
        if let task = currentTask {
            print("[RoutineRunnerView] Task '\(task.taskName ?? "")' isChecklistTask: \(task.isChecklistTask), checklistItems: \(task.checklistItems?.debugDescription ?? "nil")")
        }
        return isChecklist
    }
    
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
        let actualFinishTime = runner.actualCompletionTime ?? Date()
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
                Group {
                    // Use special layout for No Timers mode
                    if settingsManager.noTimersMode {
                    VStack(spacing: 0) {
                        // Top bar with X and routine info
                        HStack {
                            Button(action: {
                                showTaskList = true
                            }) {
                                Text("\(runner.routine.name ?? "Routine") \(runner.currentTaskIndex + 1)/\(runner.scheduledTasks.count)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
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
                        .padding(.bottom, 8)
                        
                        if isChecklistTask {
                            // Checklist task layout
                            Text(runner.currentTaskName)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            
                            // Checklist items
                            ChecklistTaskView(runner: runner)
                                .frame(maxHeight: .infinity)
                                .padding(.horizontal)
                        } else {
                            // Regular task layout - centered task name
                            Spacer()
                            
                            Text(runner.currentTaskName)
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal)
                            
                            Spacer()
                        }
                        
                        // Bottom section with buttons and slide to complete
                        VStack(spacing: 20) {
                            // Two buttons: Delay and Skip
                            HStack(spacing: 60) {
                                // Delay (hourglass)
                                Button(action: {
                                    logger.info("Delay button tapped.")
                                    runner.delayCurrentTask()
                                }) {
                                    Image(systemName: "hourglass")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 40))
                                }
                                .disabled(runner.isRoutineComplete || !runner.canDelayCurrentTask)
                                
                                // Skip
                                Button(action: {
                                    logger.info("Skip button tapped.")
                                    runner.skipCurrentTask()
                                }) {
                                    Image(systemName: "forward.fill")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 40))
                                }
                                .disabled(runner.isRoutineComplete)
                            }
                            .padding(.bottom, 10)
                            
                            // Slide to complete at the bottom
                            SlideToCompleteView {
                                logger.info("Task completed via slide.")
                                runner.markTaskComplete()
                            }
                            .disabled(runner.isRoutineComplete)
                            .frame(height: 60)
                            .padding(.horizontal)
                            .padding(.bottom, 30)
                        }
                    }
                } else {
                    // Original layout for when timers are enabled
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
                                        .foregroundColor(infoMode && highlightedElement == "routine" ? .blue : .primary)
                                        .saturation(elementSaturation(for: "routine"))
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
                        
                        // Show either checklist view or regular task view
                        if isChecklistTask && !minimalMode {
                            // Task name at top for checklist tasks
                            Text(runner.currentTaskName)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(runner.isOverrun ? .red : .primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal)
                                .padding(.top, 10)
                            
                            // Checklist task view with expanded height
                            ChecklistTaskView(runner: runner)
                                .frame(maxHeight: .infinity)
                                .padding(.horizontal)
                        } else {
                            // Regular task name display
                            Text(runner.currentTaskName)
                                .font(.system(size: minimalMode ? 42 : 34, weight: .bold))
                                .foregroundColor(infoMode && highlightedElement == "title" ? .blue : (runner.isOverrun ? .red : .primary))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal)
                                .frame(minHeight: 40, maxHeight: minimalMode ? 120 : 100)
                                .padding(.top, minimalMode ? 20 : 0)
                                .saturation(infoMode && highlightedElement != "title" ? 0 : 1)
                                .onTapGesture { 
                                    if infoMode { 
                                        highlightedElement = "title" 
                                    } else {
                                        showTaskList = true
                                    }
                                }
                        }
                        
                        // Circular progress and timer (hide for checklist tasks in non-minimal mode OR when in No Timers mode)
                        if !settingsManager.noTimersMode && (!isChecklistTask || minimalMode) {
                            ZStack {
                                // Show different progress view during prep phase
                                if runner.isInPrepPhase {
                                    // Prep phase progress circle - shows remaining time as filled portion
                                    let prepProgress = currentTask?.prepTime ?? 0 > 0
                                        ? runner.prepTimeRemaining / TimeInterval(currentTask?.prepTime ?? 1)
                                        : 0

                                    Circle()
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 12)
                                        .frame(width: 280, height: 280)

                                    Circle()
                                        .trim(from: 0, to: CGFloat(prepProgress))
                                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                        .frame(width: 280, height: 280)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear(duration: 0.1), value: runner.prepTimeRemaining)
                                } else {
                                    ConcentricProgressView(
                                        outerProgress: runner.progressFraction,
                                        innerProgress: runner.taskProgressFraction,
                                        size: 280,
                                        innerProgressColor: runner.isOverrun ? .red : .blue
                                    )
                                    .saturation(elementSaturation(for: "progress"))
                                    .onTapGesture {
                                        if infoMode {
                                            highlightedElement = "progress"
                                        }
                                    }
                                }

                                // Timer display - shows prep countdown or regular timer
                                ZStack {
                                    if runner.isInPrepPhase {
                                        // Prep phase display
                                        VStack(spacing: 8) {
                                            Text("GET READY")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.orange)

                                            Text(String(format: "%.0f", ceil(runner.prepTimeRemaining)))
                                                .font(.system(size: 80, weight: .bold).monospacedDigit())
                                                .foregroundColor(.orange)

                                            // Skip prep button
                                            Button(action: {
                                                logger.info("Skip prep tapped")
                                                runner.skipPrepPhase()
                                            }) {
                                                Text("Skip")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    } else {
                                        Text(runner.remainingTimeString)
                                            .font(.system(size: 64, weight: .light).monospacedDigit())
                                            .foregroundColor(runner.isRunning ? (runner.isOverrun ? .red : .blue) : .gray)
                                            .saturation(elementSaturation(for: "timer"))

                                        // Pause icon overlay when paused
                                        if !runner.isRunning && !runner.isRoutineComplete {
                                            Image(systemName: "pause.circle.fill")
                                                .font(.system(size: 140))
                                                .foregroundColor(.black)
                                                .opacity(0.8)
                                        }
                                    }
                                }
                                .onTapGesture {
                                    if infoMode {
                                        highlightedElement = "timer"
                                    } else if !runner.isInPrepPhase {
                                        // Toggle pause/play only when not in prep phase
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
                        }
                        
                        // Add flexible spacer in minimal mode to push content down
                        if minimalMode {
                            Spacer()
                        }
                        
                        // Schedule status with spend time button (hide in minimal mode, for checklist tasks, and in No Timers mode)
                        if !minimalMode && !isChecklistTask && !settingsManager.noTimersMode {
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
                                                .foregroundColor(scheduleColor())

                                            Text(runner.scheduleOffsetString)
                                                .foregroundColor(scheduleColor())
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
                            .saturation(elementSaturation(for: "schedule"))
                            .disabled(!runner.canSpendTime && !infoMode)
                            .padding(.top, 30)
                        }
                        
                        // Remove spacers to keep buttons higher

                        // Action buttons - hidden during prep phase
                        HStack(spacing: 40) {
                            // Interruption - far left (only in detailed mode, hidden in No Timers mode)
                            if !settingsManager.noTimersMode {
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
                                .saturation(elementSaturation(for: "interrupt"))
                                .disabled((runner.isRoutineComplete || runner.isHandlingInterruption) && !infoMode)
                                .opacity(minimalMode ? 0 : 1)
                                .scaleEffect(minimalMode ? 0.5 : 1)
                                .animation(.easeInOut(duration: 0.3), value: minimalMode)
                            }
                                
                            // Delay (hourglass) - visible in both modes
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
                            .saturation(elementSaturation(for: "delay"))
                            .disabled((runner.isRoutineComplete || !runner.canDelayCurrentTask) && !infoMode)
                                
                            // Toggle mode button - changes based on mode
                            Button(action: {
                                if infoMode {
                                    highlightedElement = "minimal"
                                } else {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        minimalMode.toggle()
                                    }
                                }
                            }) {
                                ZStack {
                                    Image(systemName: "plus")
                                        .foregroundColor(infoMode && highlightedElement == "minimal" ? .blue : .gray)
                                        .font(.title2)
                                        .opacity(minimalMode ? 1 : 0)
                                        .scaleEffect(minimalMode ? 1 : 0.5)
                                    
                                    Image(systemName: "minus")
                                        .foregroundColor(infoMode && highlightedElement == "minimal" ? .blue : .gray)
                                        .font(.title2)
                                        .opacity(minimalMode ? 0 : 1)
                                        .scaleEffect(minimalMode ? 0.5 : 1)
                                }
                            }
                            .saturation(elementSaturation(for: "minimal"))
                                
                            // Skip - visible in both modes
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
                            .saturation(elementSaturation(for: "skip"))
                            .disabled(runner.isRoutineComplete && !infoMode)
                                
                            // Continue in Background - far right (only in detailed mode, hidden in No Timers mode)
                            if !settingsManager.noTimersMode {
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
                                .saturation(elementSaturation(for: "background"))
                                .disabled(!runner.canMoveToBackground && !infoMode)
                                .opacity(minimalMode ? 0 : 1)
                                .scaleEffect(minimalMode ? 0.5 : 1)
                                .animation(.easeInOut(duration: 0.3), value: minimalMode)
                            }
                        }
                        .padding(.vertical, 20)
                        .animation(.easeInOut(duration: 0.3), value: minimalMode)
                        .opacity(runner.isInPrepPhase ? 0 : 1)

                        // Slide to complete
                        ZStack {
                            SlideToCompleteView {
                                logger.info("Task completed via slide.")
                                runner.markTaskComplete()
                            }
                            .disabled(runner.isRoutineComplete)
                            .saturation(elementSaturation(for: "complete"))
                            .padding(.horizontal)
                            .onTapGesture {
                                if infoMode {
                                    highlightedElement = "complete"
                                }
                            }
                        }
                        .opacity(runner.isInPrepPhase ? 0 : 1)

                        // Bottom spacing
                        Spacer().frame(height: 20)
                    }
                    .padding(.bottom, minimalMode ? 120 : 100) // Increased padding in detailed mode to lift buttons and slider higher
                    .background(Color(.systemGray6))
                    .onAppear {
                        // Start the timer automatically when view appears
                        // Skip if already running (e.g., prep phase auto-started) or in prep phase
                        if !runner.isRunning && !runner.isInPrepPhase && !runner.isRoutineComplete && runner.currentTaskIndex >= 0 {
                            runner.startTimer()
                        }

                        // Force detail view for checklist tasks
                        if isChecklistTask && minimalMode {
                            minimalMode = false
                        }
                    }
                    .onChange(of: runner.currentTaskIndex) { _, _ in
                        // Force detail view when switching to a checklist task
                        if isChecklistTask && minimalMode {
                            minimalMode = false
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
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
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
                                
                                VStack(spacing: 12) {
                                    Text(infoTitle(for: element))
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    
                                    Text(infoText(for: element))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                                )
                                .frame(maxWidth: min(geometry.size.width * 0.85, 320))
                                .onTapGesture {
                                    highlightedElement = nil
                                }
                                    .padding(.horizontal)
                                    .padding(.vertical, getVerticalPadding(for: element, in: geometry.size))
                                
                                if isAboveCenter {
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } // End of ZStack for original layout
                } // End of else block for original layout
                } // End of Group
                .sheet(isPresented: $showTaskList) {
                    RoutineRunnerDetailView(
                        runner: runner
                    )
                }
                .sheet(isPresented: $runner.showSpendTimeSheet) {
                    SpendOverUnderView(runner: runner)
                }
                .sheet(isPresented: $showEditDurationSheet) {
                    if let taskAnalytics = taskToEdit {
                        EditTaskDurationView(
                            taskName: taskAnalytics.taskName,
                            currentDuration: taskAnalytics.expectedDuration,
                            viewContext: viewContext,
                            onSave: {
                                showEditDurationSheet = false
                                taskToEdit = nil
                            }
                        )
                    }
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
                .onDisappear {
                    logger.info("🔵 VIEW DISAPPEAR: RoutineRunnerView is disappearing")
                    // End Live Activity when leaving the view
                    runner.endLiveActivity()
                }
            } else {
                // Routine complete view
                ScrollView {
                    VStack(spacing: 30) {
                        // Add some top padding instead of Spacer
                        Color.clear.frame(height: 40)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        
                        Text("Routine Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    
                    // Display original vs actual finish times (hide in No Timers mode)
                    if !settingsManager.noTimersMode {
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
                    }
                    
                    // Time Savings Analytics (hide in No Timers mode)
                    if !settingsManager.noTimersMode {
                        VStack(spacing: 15) {
                            Text("Time Analysis")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 10) {
                                // Time saved by skipping tasks
                                if runner.timeSavedBySkipping > 0 {
                                    HStack {
                                        Image(systemName: "forward.fill")
                                            .foregroundColor(.orange)
                                        Text("Time saved by skipping tasks:")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatTimeInterval(runner.timeSavedBySkipping))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.orange)
                                    }
                                    .font(.system(size: 16))
                                }
                                
                                // Time saved by faster completion
                                if runner.timeSavedByFasterCompletion > 0 {
                                    HStack {
                                        Image(systemName: "hare.fill")
                                            .foregroundColor(.green)
                                        Text("Time saved by faster completion:")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatTimeInterval(runner.timeSavedByFasterCompletion))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.green)
                                    }
                                    .font(.system(size: 16))
                                }
                                
                                // Time lost by slower completion
                                if runner.timeLostBySlowerCompletion > 0 {
                                    HStack {
                                        Image(systemName: "tortoise.fill")
                                            .foregroundColor(.red)
                                        Text("Extra time on tasks:")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatTimeInterval(runner.timeLostBySlowerCompletion))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.red)
                                    }
                                    .font(.system(size: 16))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // Tasks with significant time differences
                    let thresholdOptions = [(0.1, "10%"), (0.2, "20%"), (0.3, "30%"), (0.4, "40%"), (0.5, "50%")]
                    let filteredTasks = runner.tasksWithDifferenceThreshold(percentThreshold: selectedThreshold)

                    if !filteredTasks.isEmpty || !runner.taskAnalytics.filter({ !$0.wasSkipped && $0.actualDuration != nil }).isEmpty {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Tasks to Review")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Menu {
                                    ForEach(thresholdOptions, id: \.0) { threshold, label in
                                        Button(action: {
                                            selectedThreshold = threshold
                                        }) {
                                            Label(label, systemImage: selectedThreshold == threshold ? "checkmark" : "")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("≥ \(Int(selectedThreshold * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                                }
                            }

                            if filteredTasks.isEmpty {
                                Text("No tasks with ≥\(Int(selectedThreshold * 100))% time difference")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                Text("Tasks with ≥\(Int(selectedThreshold * 100))% time difference:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            ForEach(filteredTasks, id: \.taskName) { analytics in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(analytics.taskName)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if let avgTime = analytics.averageCompletionTime, analytics.completionCount >= 10 {
                                            Text("Avg: \(formatDuration(avgTime)) (\(analytics.completionCount)x)")
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    Spacer()
                                    if let actual = analytics.actualDuration {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Expected: \(formatDuration(analytics.expectedDuration))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("Actual: \(formatDuration(actual))")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(analytics.timeDifference > 0 ? .green : .red)
                                        }
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    logger.info("Task tapped: \(analytics.taskName)")
                                    if let uuid = analytics.taskUUID {
                                        logger.info("Task UUID: \(uuid)")
                                        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
                                        fetchRequest.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
                                        fetchRequest.fetchLimit = 1
                                        if let task = try? viewContext.fetch(fetchRequest).first {
                                            logger.info("Found CDTask, showing edit sheet")
                                            cdTaskToEdit = task
                                        } else {
                                            logger.error("Could not fetch CDTask for UUID: \(uuid)")
                                        }
                                    } else {
                                        logger.error("Task UUID is nil for: \(analytics.taskName)")
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.headline)
                    .padding()
                    .frame(width: 200)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    // Add some bottom padding
                    Color.clear.frame(height: 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .fullScreenCover(item: $cdTaskToEdit) { task in
                    AddTaskView(task: task.toDomainModel()) { updatedTask in
                        task.updateCDTask(from: updatedTask)
                        try? viewContext.save()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        // Removed onDisappear to allow routine to continue when switching views
    }
    
    // Helper function to format time intervals
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    // Helper function to format duration with minutes and seconds
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    // Info mode helper functions
    private func elementSaturation(for element: String) -> Double {
        if !infoMode { return 1.0 }
        return highlightedElement == element ? 1.0 : 0.0
    }
    
    func infoTitle(for element: String) -> String {
        switch element {
        case "routine": return "Routine Info"
        case "title": return "Current Task"
        case "comingUp": return "Next Task"
        case "timer": return "Task Timer"
        case "progress": return "Progress Rings"
        case "schedule": return "Schedule Status"
        case "skip": return "Skip Task"
        case "delay": return "Delay Task"
        case "minimal": return "Minimal View"
        case "interrupt": return "Interruption"
        case "background": return "Background Task"
        case "complete": return "Complete Task"
        default: return ""
        }
    }
    
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
        let position = infoPosition(for: element, in: size)
        let isBottomElement = position.y > size.height * 0.7
        
        switch element {
        case "routine": return 120
        case "title": return 180
        case "comingUp": return 240
        case "progress", "timer": return 60
        case "schedule": return 100
        case "interrupt", "delay", "minimal", "skip", "background": 
            // For bottom buttons, show info above them
            return isBottomElement ? 180 : 60
        case "complete": 
            // Show above the slide to complete
            return 120
        default: return 60
        }
    }
}

struct EditTaskDurationView: View {
    let taskName: String
    let currentDuration: TimeInterval
    let viewContext: NSManagedObjectContext
    let onSave: () -> Void

    @State private var minDurationMinutes: String = ""
    @State private var maxDurationMinutes: String = ""
    @State private var isVariableDuration: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "EditTaskDurationView")

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Task")) {
                    Text(taskName)
                        .font(.headline)
                }

                Section(header: Text("Duration Type")) {
                    Toggle("Variable Duration", isOn: $isVariableDuration.animation())
                }

                Section(header: Text("Duration (minutes)")) {
                    if isVariableDuration {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Minimum")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Min", text: $minDurationMinutes)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading) {
                                Text("Maximum")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Max", text: $maxDurationMinutes)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                    } else {
                        TextField("Duration", text: $minDurationMinutes)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }

                Section {
                    Text("Current duration: \(Int(currentDuration/60)) minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Task Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTaskDuration()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Initialize with current duration
            let minutes = Int(currentDuration / 60)
            minDurationMinutes = String(minutes)
            maxDurationMinutes = String(minutes)
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func saveTaskDuration() {
        // Validate input
        guard let minDuration = Int(minDurationMinutes), minDuration > 0 else {
            alertMessage = "Please enter a valid minimum duration"
            showAlert = true
            return
        }

        let maxDuration: Int
        if isVariableDuration {
            guard let max = Int(maxDurationMinutes), max > 0 else {
                alertMessage = "Please enter a valid maximum duration"
                showAlert = true
                return
            }
            guard max >= minDuration else {
                alertMessage = "Maximum duration must be greater than or equal to minimum duration"
                showAlert = true
                return
            }
            maxDuration = max
        } else {
            maxDuration = minDuration
        }

        // Find and update the task in Core Data
        let fetchRequest: NSFetchRequest<CDTask> = CDTask.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "taskName == %@", taskName)
        fetchRequest.fetchLimit = 1

        do {
            let tasks = try viewContext.fetch(fetchRequest)
            if let task = tasks.first {
                task.minDuration = Int32(minDuration)
                task.maxDuration = Int32(maxDuration)

                try viewContext.save()
                logger.info("Updated task '\(taskName)' duration: min=\(minDuration), max=\(maxDuration)")

                onSave()
                dismiss()
            } else {
                alertMessage = "Task not found in database"
                showAlert = true
            }
        } catch {
            logger.error("Failed to update task duration: \(error.localizedDescription)")
            alertMessage = "Failed to save changes"
            showAlert = true
        }
    }
}
