import SwiftUI
import CoreData
import OSLog

struct RoutineSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var viewModel: RoutineViewModel
    @ObservedObject private var settingsManager = SettingsManager.shared
    
    @FetchRequest private var cdRoutines: FetchedResults<CDRoutine>
    
    @State private var selectedRoutine: CDRoutine?
    @State private var selectedTime: Date = Date()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var navigateToRunner: Bool = false
    @State private var showSchedulePreviewModal: Bool = false
    @State private var scheduleForPreview: [ScheduledTask]? = nil
    @State private var expectedPreviewDuration: Int? = nil
    @State private var showRunFromSheet: Bool = false
    @State private var runFromStartIndex: Int = -1
    @State private var runFromTask: CDTask? = nil
    @State private var scheduleForRunFrom: [ScheduledTask]? = nil
    @State private var showTempRoutineEntry = false
    @State private var infoMode = false
    @StateObject private var tempRunnerWrapper = TempRunnerWrapper()
    @State private var showTempRunner = false
    
    @State private var runnerInstance: RoutineRunner? = nil
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    private let logger = AppLogger.create(subsystem: "com.app.RoutineSelectionView", category: "UI")

    init(viewModel: RoutineViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        let fetchRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDRoutine.name, ascending: true)]
        _cdRoutines = FetchRequest(fetchRequest: fetchRequest, animation: .default)
    }
    
    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
    
    private func calculateTotalMinDuration(routine: CDRoutine) -> Int {
        guard let tasks = routine.taskRelations as? Set<CDRoutineTask> else { return 0 }
        return tasks.reduce(0) { $0 + Int($1.task?.minDuration ?? 0) }
    }
    
    private func calculateDurations(for routine: CDRoutine?) -> DurationInfo {
        guard let routine = routine else {
            return DurationInfo(essential: 0, coreAndEssential: 0, all: 0)
        }

        let scheduler = CoreDataTaskScheduler(context: viewContext)
        let essentialTimeSeconds = scheduler.estimateScheduleDuration(for: routine, includingLevel: 3)
        let coreEssentialTimeSeconds = scheduler.estimateScheduleDuration(for: routine, includingLevel: 2)
        let allTimeSeconds = scheduler.estimateScheduleDuration(for: routine, includingLevel: 1)

        // Use floor instead of round to avoid showing durations that might not fit
        let essentialMinutes = Int(essentialTimeSeconds / 60)
        let coreEssentialMinutes = Int(coreEssentialTimeSeconds / 60)
        let allMinutes = Int(allTimeSeconds / 60)

        logger.debug("Scheduler Estimated Durations for '\(routine.name ?? "")': E=\(essentialMinutes)m, C+E=\(coreEssentialMinutes)m, All=\(allMinutes)m")

        return DurationInfo(
            essential: essentialMinutes,
            coreAndEssential: coreEssentialMinutes,
            all: allMinutes
        )
    }
    
    private func getDefaultRoutine() -> CDRoutine? {
        let hour = Calendar.current.component(.hour, from: Date())
        
        logger.debug("Current hour for default routine selection: \(hour)")

        let routineNameLowercased: String
        
        if hour >= 3 && hour < 12 {
            routineNameLowercased = "morning"
            logger.debug("Selecting 'morning' routine.")
        } else if hour >= 12 && hour < 19 {
            routineNameLowercased = "catch up"
            logger.debug("Selecting 'catch up' routine.")
        } else {
            routineNameLowercased = "evening"
            logger.debug("Selecting 'evening' routine.")
        }

        let selectedRoutine = cdRoutines.first { routine in
            (routine.name ?? "").lowercased().contains(routineNameLowercased)
        }
        
        if selectedRoutine == nil {
            logger.warning("No routine found containing '\(routineNameLowercased)'. Falling back to the first available routine.")
        }
        
        return selectedRoutine ?? cdRoutines.first
    }
    
    private func updateTimeForDuration(_ minutes: Int) {
        let bufferMinutes = settingsManager.scheduleBufferMinutes
        let totalMinutesToAdd = minutes + bufferMinutes
        let newTime = Calendar.current.date(byAdding: .minute, value: totalMinutesToAdd, to: Date()) ?? Date()
        selectedTime = newTime
        logger.debug("Updated selected end time based on duration: \(minutes)m + \(bufferMinutes)m buffer -> \(newTime)")
    }
    
    private func getAvailableTimeInMinutes() -> Int {
        let interval = selectedTime.timeIntervalSince(Date())
        let minutes = Int(round(interval / 60)) // Round to nearest minute to avoid edge cases
        logger.debug("Calculated available time: \(minutes) minutes until \(selectedTime)")
        return max(0, minutes) // Ensure non-negative
    }
    
    private func determineSelectedDurationLevel(durations: DurationInfo) -> Int {
        let availableMinutes = getAvailableTimeInMinutes()
        
        // Check against durations that already include buffer
        if availableMinutes >= durations.all + settingsManager.scheduleBufferMinutes {
            return 3 // All tasks
        } else if availableMinutes >= durations.coreAndEssential + settingsManager.scheduleBufferMinutes {
            return 2 // Core + Essential
        } else if availableMinutes >= durations.essential + settingsManager.scheduleBufferMinutes {
            return 1 // Essential only
        }
        return 0 // Not enough time for any
    }
    
    private func updateTimeToNow() {
        let currentInterval = selectedTime.timeIntervalSince(Date())
        if currentInterval > 0 {
            selectedTime = Date().addingTimeInterval(currentInterval)
        }
    }
    
    private var canScheduleEssentialTasks: Bool {
        guard let routine = selectedRoutine else {
            // If no routine is selected, we can't schedule anything.
            return false
        }
        let durations = calculateDurations(for: routine)
        let availableMinutes = getAvailableTimeInMinutes()
        
        // Check if we can schedule ANY tasks (not just essential)
        // This allows running routines even when all essential tasks are done for the day
        if durations.all > 0 && availableMinutes >= 1 {
            // We have at least some tasks available and at least 1 minute
            return true
        }
        
        // Original logic for essential tasks
        guard durations.essential > 0 else {
            logger.debug("Cannot schedule essential tasks for '\(routine.name ?? "")' because essential duration is 0.")
            return false
        }
        let canSchedule = availableMinutes >= durations.essential
        if !canSchedule {
            logger.debug("Cannot schedule essential tasks for '\(routine.name ?? "")'. Available: \(availableMinutes)m, Required: \(durations.essential)m")
        }
        return canSchedule
    }
    
    var body: some View {
        return ZStack {
            VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 20) {
                // Combined routine and time section
                HStack(spacing: 16) {
                    routinePickerSection
                    timeSelectionSection
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 1)
                .padding(.horizontal)

                if let routine = selectedRoutine {
                    durationOptionsSection(routine: routine)
                }
            }
            
            Spacer()
            
            bottomButtonsSection
            
            if let runner = runnerInstance {
                NavigationLink(
                    destination: RoutineRunnerView(runner: runner),
                    isActive: $navigateToRunner
                ) { EmptyView() }
            }
        } // End of VStack
        } // End of ZStack
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Select Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                InfoButton(showInfo: $infoMode)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showTempRoutineEntry = true
                }) {
                    Image(systemName: "timer")
                }
            }
        }
        .fullScreenCover(isPresented: $showSchedulePreviewModal) {
            if let schedule = scheduleForPreview, let routine = selectedRoutine {
                SchedulePreviewView(
                    initialSchedule: schedule,
                    routine: routine,
                    originalFinishingTime: selectedTime,
                    expectedDurationMinutes: expectedPreviewDuration,
                    runnerInstance: $runnerInstance,
                    navigateToRunner: $navigateToRunner
                )
            } else {
                Text("Error: Missing data for preview.")
                    .padding()
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showRunFromSheet) {
            if let routine = selectedRoutine, let schedule = scheduleForRunFrom {
                RunFromSelectionView(routine: routine, scheduledTasks: schedule, selectedStartIndex: $runFromStartIndex)
                    .onDisappear {
                        // When sheet dismisses, check if a task was selected
                        if runFromStartIndex >= 0 {
                            // Run from the selected index in the scheduled tasks
                            runRoutineFromScheduledIndex(runFromStartIndex)
                            runFromStartIndex = -1 // Reset for next use
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showTempRoutineEntry) {
            TempRoutineEntryView(onStartTasks: { tasks in
                logger.info("Received \(tasks.count) tasks from TempRoutineEntryView")
                logger.info("Tasks details: \(tasks.map { $0.name }.joined(separator: ", "))")
                
                // Create the runner immediately with the tasks
                let runner = TempRoutineRunner(tasks: tasks)
                logger.info("Created TempRoutineRunner instance: \(Unmanaged.passUnretained(runner).toOpaque())")
                
                // Store in wrapper
                tempRunnerWrapper.runner = runner
                logger.info("Stored runner in wrapper. Runner is now: \(tempRunnerWrapper.runner != nil ? "set" : "nil")")
                
                // Verify it's still there
                if tempRunnerWrapper.runner == nil {
                    logger.error("Runner became nil immediately after setting in wrapper!")
                } else {
                    logger.info("Runner verified as non-nil in wrapper")
                    logger.info("Wrapper runner has \(tempRunnerWrapper.runner!.tasks.count) tasks")
                }
                
                // Set flag to show fullScreenCover first
                showTempRunner = true
                
                // Then dismiss sheet with minimal delay for animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showTempRoutineEntry = false
                }
            })
        }
        .fullScreenCover(isPresented: $showTempRunner, onDismiss: {
            logger.info("fullScreenCover dismissed")
            TempRoutineStorage.clear()
            tempRunnerWrapper.runner = nil
        }) {
            Group {
                if let runner = tempRunnerWrapper.runner {
                    TempRoutineRunnerView(runner: runner)
                        .onAppear {
                            logger.info("TempRoutineRunnerView appeared with runner: \(Unmanaged.passUnretained(runner).toOpaque())")
                            logger.info("Runner has \(runner.tasks.count) tasks")
                            logger.info("First task: \(runner.tasks.first?.name ?? "none")")
                        }
                } else {
                    VStack {
                        Text("Error: Runner not initialized")
                            .foregroundColor(.red)
                            .font(.headline)
                        
                        Text("Runner is nil in wrapper when presenting fullScreenCover")
                            .foregroundColor(.secondary)
                            .padding(.bottom)
                        
                        Button("Dismiss") {
                            showTempRunner = false
                            logger.error("User dismissed error screen - runner was nil in wrapper")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .onAppear {
                        logger.error("fullScreenCover presented but runner is nil in wrapper")
                        logger.error("showTempRunner: \(showTempRunner), wrapper.runner: \(tempRunnerWrapper.runner != nil ? "exists" : "nil")")
                    }
                }
            }
        }
        .onChange(of: scheduleForRunFrom) { schedule in
            if schedule != nil {
                // Schedule is ready, show the sheet
                showRunFromSheet = true
            }
        }
        .onAppear {
            logger.info("RoutineSelectionView appeared.")
            if selectedRoutine == nil {
                selectedRoutine = getDefaultRoutine()
                logger.info("Selected default routine: \(selectedRoutine?.name ?? "None")")
            }
            
            // Set default time to 1 hour from now if not already set
            if selectedTime <= Date() {
                selectedTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                logger.info("Set default time to 1 hour from now")
            }
        }
        .onReceive(timer) { _ in
            updateTimeToNow()
        }
        .infoOverlay(
            showInfo: $infoMode,
            title: "Schedule",
            description: "Select a routine and finish time. The app will schedule tasks based on available time. Use preview to adjust tasks. Long-press run buttons for more options."
        )
    }
    
    private var routinePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routine")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("Select Routine", selection: $selectedRoutine) {
                ForEach(cdRoutines) { cdRoutine in
                    Text(cdRoutine.name ?? "Unnamed Routine")
                        .tag(cdRoutine as CDRoutine?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            .onChange(of: selectedRoutine) { newRoutine in
                logger.info("Routine selection changed to: \(newRoutine?.name ?? "None")")
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var timeSelectionSection: some View {
        Group {
            if !settingsManager.noTimersMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finishing Time")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DatePicker("Select End Time",
                               selection: $selectedTime,
                               in: Date()...,
                               displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .onChange(of: selectedTime) { newTime in
                            logger.debug("Selected end time changed to: \(newTime)")
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func durationOptionsSection(routine: CDRoutine) -> some View {
        let durations = calculateDurations(for: routine)
        let selectedLevel = determineSelectedDurationLevel(durations: durations)
        let bufferMinutes = settingsManager.scheduleBufferMinutes
        
        return VStack(spacing: 12) {
            HStack {
                Text("Quick Duration")
                    .font(.headline)
                Spacer()
                if bufferMinutes > 0 {
                    Text("(includes \(bufferMinutes)m buffer)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                DurationButton(title: "Essential", duration: durations.essential + bufferMinutes, color: .red, isSelected: selectedLevel == 1) {
                    updateTimeForDuration(durations.essential)
                    logger.info("Duration button tapped: Essential")
                }
                DurationButton(title: "Core", duration: durations.coreAndEssential + bufferMinutes, color: .orange, isSelected: selectedLevel == 2) {
                    updateTimeForDuration(durations.coreAndEssential)
                    logger.info("Duration button tapped: Core + Essential")
                }
                DurationButton(title: "All", duration: durations.all + bufferMinutes, color: .green, isSelected: selectedLevel >= 3) {
                    updateTimeForDuration(durations.all)
                    logger.info("Duration button tapped: All Tasks")
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
        .padding(.horizontal)
    }
    
    private var bottomButtonsSection: some View {
        HStack(spacing: 12) {
            let isDisabled = selectedRoutine == nil || isLoading || !canScheduleEssentialTasks

            Button {
                viewScheduledRoutine()
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(height: 22)
                } else {
                    Text("Preview")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDisabled ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(isDisabled)

            Button {
                runRoutineDirectly()
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(height: 22)
                } else {
                    Text("Run")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDisabled ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(isDisabled)
            .contextMenu {
                Button(action: {
                    prepareRunFromSelection()
                }) {
                    Label("Run from...", systemImage: "play.circle")
                }
                .disabled(selectedRoutine == nil)
                
                Button(action: {
                    runRoutineRandomly()
                }) {
                    Label("Run Random", systemImage: "shuffle")
                }
                .disabled(isDisabled)
            }
        }
        .padding(.horizontal)
        .padding(.vertical)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 2, y: -2)
        )
    }
    
    private func prepareRunFromSelection() {
        logger.info("Preparing 'Run from' selection.")
        isLoading = true
        errorMessage = ""
        showError = false
        scheduleForRunFrom = nil
        
        Task {
            do {
                let schedule = try await generateSchedule()
                DispatchQueue.main.async {
                    self.scheduleForRunFrom = schedule
                    self.isLoading = false
                    logger.info("Generated schedule with \(schedule.count) tasks for 'run from' selection")
                }
            } catch let error as SchedulingError {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("SchedulingError during run from preparation: \(error.localizedDescription)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("Unexpected error during run from preparation: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func runRoutineFromScheduledIndex(_ startIndex: Int) {
        logger.info("'Run from scheduled index \(startIndex)' selected.")
        isLoading = true
        errorMessage = ""
        showError = false
        runnerInstance = nil
        
        guard let schedule = scheduleForRunFrom else {
            logger.error("Missing schedule for run from index")
            isLoading = false
            return
        }
        
        guard let routine = selectedRoutine else {
            logger.error("Missing routine for run from index")
            isLoading = false
            return
        }
        
        // Remove tasks before the start index
        var adjustedSchedule = schedule
        if startIndex > 0 && startIndex < schedule.count {
            adjustedSchedule = Array(schedule.dropFirst(startIndex))
            logger.info("Starting routine from scheduled task \(startIndex + 1), removed \(startIndex) previous tasks")
        }
        
        // Clear the schedule after using it
        scheduleForRunFrom = nil
        
        DispatchQueue.main.async { [adjustedSchedule] in
            let newRunner = RoutineRunner(context: self.viewContext, routine: routine, schedule: adjustedSchedule, originalFinishingTime: self.selectedTime)
            self.runnerInstance = newRunner
            self.isLoading = false
            self.navigateToRunner = true
            logger.info("Navigating to RoutineRunner from scheduled index \(startIndex).")
        }
    }
    
    
    private func generateSchedule() async throws -> [ScheduledTask] {
        guard let routine = selectedRoutine else {
            logger.warning("Schedule generation attempted with no routine selected.")
            throw SchedulingError.routineLoadError
        }

        let currentTime = Date()
        let availableTime = selectedTime.timeIntervalSince(currentTime)
        
        logger.debug("=== GENERATE SCHEDULE DEBUG ===")
        logger.debug("Current time: \(currentTime)")
        logger.debug("Selected finishing time: \(selectedTime)")
        logger.debug("Available time (seconds): \(availableTime)")
        logger.debug("Available time (minutes): \(availableTime / 60)")
        
        // Allow a small tolerance for timing edge cases (2 minutes)
        let timingTolerance: TimeInterval = 120 // 2 minutes in seconds
        
        guard availableTime > -timingTolerance else {
            logger.error("FAIL: Available time check failed!")
            logger.error("Available: \(availableTime)s, Required: > \(-timingTolerance)s")
            logger.warning("Schedule generation attempted with insufficient time (\(availableTime)s). End time: \(selectedTime)")
            throw SchedulingError.insufficientTime
        }
        
        // Subtract buffer from available time for scheduling
        let bufferSeconds = TimeInterval(settingsManager.scheduleBufferMinutes * 60)
        let schedulingTime = availableTime - bufferSeconds
        
        logger.debug("Buffer (minutes): \(settingsManager.scheduleBufferMinutes)")
        logger.debug("Buffer (seconds): \(bufferSeconds)")
        logger.debug("Scheduling time after buffer: \(schedulingTime)s (\(schedulingTime / 60)m)")
        
        // Allow slight negative time with tolerance (user just selected this duration)
        guard schedulingTime > -timingTolerance else {
            logger.error("FAIL: Scheduling time check failed!")
            logger.error("Scheduling time: \(schedulingTime)s, Required: > \(-timingTolerance)s")
            logger.warning("No time available after buffer. Available: \(Int(availableTime/60))m, Buffer: \(settingsManager.scheduleBufferMinutes)m")
            throw SchedulingError.insufficientTime
        }
        
        // Ensure scheduler gets at least 0 seconds (not negative)
        let actualSchedulingTime = max(0, schedulingTime)
        
        logger.debug("Actual scheduling time passed to scheduler: \(actualSchedulingTime)s (\(actualSchedulingTime / 60)m)")
        logger.debug("=== END GENERATE SCHEDULE DEBUG ===")

        logger.info("Starting schedule generation for '\(routine.name ?? "Unnamed")' with \(Int(actualSchedulingTime / 60)) mins available (total: \(Int(availableTime / 60))m minus \(settingsManager.scheduleBufferMinutes)m buffer).")
        let scheduler = CoreDataTaskScheduler(context: viewContext)

        let schedule = try scheduler.generateSchedule(for: routine, availableTime: actualSchedulingTime)

        guard !schedule.isEmpty else {
            logger.warning("Schedule generation for '\(routine.name ?? "Unnamed")' resulted in 0 tasks. Throwing schedulingFailure.")
            throw SchedulingError.schedulingFailure
        }

        logger.info("Successfully generated schedule with \(schedule.count) tasks for '\(routine.name ?? "Unnamed")'.")
        return schedule
    }
    
    private func runRoutineDirectly() {
        logger.info("'Run' button tapped.")
        isLoading = true
        errorMessage = ""
        showError = false
        runnerInstance = nil

        Task {
            do {
                let schedule = try await generateSchedule()
                guard let routine = selectedRoutine else {
                    logger.error("Defensive check failed: Routine became unselected after schedule generation.")
                    throw SchedulingError.routineLoadError
                }

                DispatchQueue.main.async { [schedule] in
                    let newRunner = RoutineRunner(context: self.viewContext, routine: routine, schedule: schedule, originalFinishingTime: self.selectedTime)
                    self.runnerInstance = newRunner
                    self.isLoading = false
                    self.navigateToRunner = true
                    logger.info("Navigating directly to RoutineRunner.")
                }
            } catch let error as SchedulingError {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("SchedulingError during direct run: \(error.localizedDescription)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("Unexpected error during direct run: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func runRoutineRandomly() {
        logger.info("'Random' button tapped.")
        isLoading = true
        errorMessage = ""
        showError = false
        runnerInstance = nil

        Task {
            do {
                let schedule = try await generateSchedule()
                guard let routine = selectedRoutine else {
                    logger.error("Defensive check failed: Routine became unselected after schedule generation.")
                    throw SchedulingError.routineLoadError
                }

                // Randomize the schedule order
                let randomizedSchedule = schedule.shuffled()
                logger.info("Randomized schedule for routine '\(routine.name ?? "Unnamed")' - original order: \(schedule.count) tasks, randomized order applied.")

                DispatchQueue.main.async { [randomizedSchedule] in
                    let newRunner = RoutineRunner(context: self.viewContext, routine: routine, schedule: randomizedSchedule, originalFinishingTime: self.selectedTime)
                    self.runnerInstance = newRunner
                    self.isLoading = false
                    self.navigateToRunner = true
                    logger.info("Navigating to RoutineRunner with randomized schedule.")
                }
            } catch let error as SchedulingError {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("SchedulingError during random run: \(error.localizedDescription)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("Unexpected error during random run: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func viewScheduledRoutine() {
        logger.info("'Preview' button tapped.")
        isLoading = true
        errorMessage = ""
        showError = false
        scheduleForPreview = nil
        
        logger.debug("=== VIEW SCHEDULED ROUTINE DEBUG ===")
        
        // Calculate expected duration based on available time and what can be scheduled
        // The scheduler will only use (availableTime - buffer) for scheduling
        if let routine = selectedRoutine {
            let durations = calculateDurations(for: routine)
            let bufferMinutes = settingsManager.scheduleBufferMinutes
            let availableMinutes = getAvailableTimeInMinutes()
            let schedulingMinutes = availableMinutes - bufferMinutes
            
            logger.debug("Routine: \(routine.name ?? "Unknown")")
            logger.debug("Durations - Essential: \(durations.essential)m, Core+Essential: \(durations.coreAndEssential)m, All: \(durations.all)m")
            logger.debug("Buffer: \(bufferMinutes)m")
            logger.debug("Available minutes: \(availableMinutes)m")
            logger.debug("Scheduling minutes (available - buffer): \(schedulingMinutes)m")
            
            // Determine what will actually be scheduled based on time available for scheduling
            // Apply same tolerance as in generateSchedule for consistency
            let timingToleranceMinutes = 2
            let expectedScheduledMinutes: Int
            
            if schedulingMinutes + timingToleranceMinutes >= durations.all {
                expectedScheduledMinutes = durations.all
                logger.debug("Expected tier: All tasks (\(durations.all)m)")
            } else if schedulingMinutes + timingToleranceMinutes >= durations.coreAndEssential {
                expectedScheduledMinutes = durations.coreAndEssential
                logger.debug("Expected tier: Core+Essential (\(durations.coreAndEssential)m)")
            } else if schedulingMinutes + timingToleranceMinutes >= durations.essential {
                expectedScheduledMinutes = durations.essential
                logger.debug("Expected tier: Essential only (\(durations.essential)m)")
            } else {
                expectedScheduledMinutes = max(0, schedulingMinutes) // What can fit
                logger.debug("Expected tier: Partial/None (only \(expectedScheduledMinutes)m can fit)")
            }
            
            // Preview should show scheduled time + buffer
            expectedPreviewDuration = expectedScheduledMinutes + bufferMinutes
            logger.debug("Expected preview duration: \(expectedPreviewDuration)m (\(expectedScheduledMinutes)m tasks + \(bufferMinutes)m buffer)")
        } else {
            expectedPreviewDuration = Int(selectedTime.timeIntervalSince(Date()) / 60)
            logger.debug("No routine selected, using time difference: \(expectedPreviewDuration)m")
        }
        
        logger.debug("=== END VIEW SCHEDULED ROUTINE DEBUG ===")

        Task {
            do {
                let schedule = try await generateSchedule()
                DispatchQueue.main.async {
                    self.scheduleForPreview = schedule
                    self.isLoading = false
                    self.showSchedulePreviewModal = true
                    logger.info("Presenting schedule preview modal.")
                }
            } catch let error as SchedulingError {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("SchedulingError during schedule preview generation: \(error)")
                    self.logger.error("Error description: \(error.localizedDescription)")
                    
                    // Add specific debugging for each error type
                    switch error {
                    case .insufficientTime:
                        self.logger.error("Error type: insufficientTime")
                    case .routineLoadError:
                        self.logger.error("Error type: routineLoadError")
                    case .schedulingFailure:
                        self.logger.error("Error type: schedulingFailure")
                    default:
                        self.logger.error("Error type: unknown")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("Unexpected error during schedule preview generation: \(error)")
                    self.logger.error("Error type: \(type(of: error))")
                }
            }
        }
    }
}

struct DurationInfo {
    let essential: Int
    let coreAndEssential: Int
    let all: Int
}

struct DurationButton: View {
    let title: String
    let duration: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(formatDuration(duration))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(isSelected ? 0.2 : 0.05))
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
