import SwiftUI
import CoreData
import OSLog

struct RoutineSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var viewModel: RoutineViewModel
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDRoutine.name, ascending: true)],
        animation: .default
    ) private var cdRoutines: FetchedResults<CDRoutine>
    
    @State private var selectedRoutine: CDRoutine?
    @State private var selectedTime: Date = Date()
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var navigateToRunner: Bool = false
    @State private var showSchedulePreviewModal: Bool = false
    @State private var scheduleForPreview: [ScheduledTask]? = nil
    @State private var showRunFromSheet: Bool = false
    @State private var runFromStartIndex: Int = 0
    @State private var showTempRoutineEntry = false
    @State private var infoMode = false
    
    @State private var runnerInstance: RoutineRunner? = nil
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    private let logger = AppLogger.create(subsystem: "com.app.RoutineSelectionView", category: "UI")
    
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

        let essentialMinutes = Int(round(essentialTimeSeconds / 60))
        let coreEssentialMinutes = Int(round(coreEssentialTimeSeconds / 60))
        let allMinutes = Int(round(allTimeSeconds / 60))

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
        let bufferMinutes = 2
        let totalMinutesToAdd = minutes + bufferMinutes
        let newTime = Calendar.current.date(byAdding: .minute, value: totalMinutesToAdd, to: Date()) ?? Date()
        selectedTime = newTime
        logger.debug("Updated selected end time based on duration: \(minutes)m + \(bufferMinutes)m buffer -> \(newTime)")
    }
    
    private func getAvailableTimeInMinutes() -> Int {
        let interval = selectedTime.timeIntervalSince(Date())
        let minutes = Int(interval / 60)
        logger.debug("Calculated available time: \(minutes) minutes until \(selectedTime)")
        return minutes
    }
    
    private func determineSelectedDurationLevel(durations: DurationInfo) -> Int {
        let availableMinutes = getAvailableTimeInMinutes()
        
        if availableMinutes > durations.all {
            return 3 // All tasks
        } else if availableMinutes > durations.coreAndEssential {
            return 2 // Core + Essential
        } else if availableMinutes > durations.essential {
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
        ZStack {
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
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Select Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    infoMode.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showTempRoutineEntry = true
                }) {
                    Image(systemName: "timer")
                }
            }
        }
        .sheet(isPresented: $showSchedulePreviewModal) {
            if let schedule = scheduleForPreview, let routine = selectedRoutine {
                SchedulePreviewView(
                    initialSchedule: schedule,
                    routine: routine,
                    originalFinishingTime: selectedTime,
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
            if let routine = selectedRoutine {
                RunFromSelectionView(routine: routine, selectedStartIndex: $runFromStartIndex)
            }
        }
        .sheet(isPresented: $showTempRoutineEntry) {
            TempRoutineEntryView()
        }
        .onChange(of: runFromStartIndex) { newIndex in
            if newIndex > 0 {
                // User selected a start point, run from that index
                runRoutineFromIndex(newIndex)
                runFromStartIndex = 0 // Reset for next use
            }
        }
        .onAppear {
            logger.info("RoutineSelectionView appeared.")
            if selectedRoutine == nil {
                selectedRoutine = getDefaultRoutine()
                logger.info("Selected default routine: \(selectedRoutine?.name ?? "None")")
            }
            
            // Set default time to essential tasks duration
            if let routine = selectedRoutine {
                let durations = calculateDurations(for: routine)
                updateTimeForDuration(durations.essential)
                logger.info("Set default time based on essential tasks duration: \(durations.essential) minutes")
            } else if selectedTime <= Date() {
                selectedTime = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
                logger.info("No routine selected, initialized selectedTime to 5 minutes in the future.")
            }
        }
        .onReceive(timer) { _ in
            updateTimeToNow()
        }
        }
        .grayscale(infoMode ? 1 : 0)
        .disabled(infoMode)
        
        // Info overlay
        if infoMode {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    infoMode = false
                }
            
            VStack(spacing: 20) {
                Text("Scheduling View")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Select a routine to run, and what time you need to be finished by. If the selected time is less than the duration of essential tasks in the future (ie. if essential tasks will take 20 minutes, it's 6pm and you select anything earlier than 6:20pm), it won't run. Use the preview button to preview, edit and re-arrange tasks that will be scheduled with the available time. Long press the run buttons to either start a routine part way through, or run a routine in a random order.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Got it") {
                    infoMode = false
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
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
                
                // Update time to essential tasks duration for the new routine
                if let routine = newRoutine {
                    let durations = calculateDurations(for: routine)
                    updateTimeForDuration(durations.essential)
                    logger.info("Updated time based on essential tasks duration: \(durations.essential) minutes")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var timeSelectionSection: some View {
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
    
    private func durationOptionsSection(routine: CDRoutine) -> some View {
        let durations = calculateDurations(for: routine)
        let selectedLevel = determineSelectedDurationLevel(durations: durations)
        
        return VStack(spacing: 12) {
            Text("Quick Duration")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                DurationButton(title: "Essential", duration: durations.essential, color: .red, isSelected: selectedLevel == 1) {
                    updateTimeForDuration(durations.essential)
                    logger.info("Duration button tapped: Essential")
                }
                DurationButton(title: "Core", duration: durations.coreAndEssential, color: .orange, isSelected: selectedLevel == 2) {
                    updateTimeForDuration(durations.coreAndEssential)
                    logger.info("Duration button tapped: Core + Essential")
                }
                DurationButton(title: "All", duration: durations.all, color: .green, isSelected: selectedLevel >= 3) {
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
                    showRunFromSheet = true
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
    
    private func runRoutineFromIndex(_ startIndex: Int) {
        logger.info("'Run from index \(startIndex)' selected.")
        isLoading = true
        errorMessage = ""
        showError = false
        runnerInstance = nil

        Task {
            do {
                var schedule = try await generateSchedule()
                guard let routine = selectedRoutine else {
                    logger.error("Defensive check failed: Routine became unselected after schedule generation.")
                    throw SchedulingError.routineLoadError
                }
                
                // Remove tasks before the start index
                if startIndex > 0 && startIndex < schedule.count {
                    schedule = Array(schedule.dropFirst(startIndex))
                    logger.info("Starting routine from task \(startIndex + 1), removed \(startIndex) previous tasks")
                }

                DispatchQueue.main.async {
                    let newRunner = RoutineRunner(context: self.viewContext, routine: routine, schedule: schedule, originalFinishingTime: self.selectedTime)
                    self.runnerInstance = newRunner
                    self.isLoading = false
                    self.navigateToRunner = true
                    logger.info("Navigating to RoutineRunner starting from task \(startIndex + 1).")
                }
            } catch let error as SchedulingError {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("SchedulingError during run from index: \(error.localizedDescription)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("Unexpected error during run from index: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func generateSchedule() async throws -> [ScheduledTask] {
        guard let routine = selectedRoutine else {
            logger.warning("Schedule generation attempted with no routine selected.")
            throw SchedulingError.routineLoadError
        }

        let availableTime = selectedTime.timeIntervalSince(Date())
        guard availableTime > 60 else {
            logger.warning("Schedule generation attempted with insufficient time (\(availableTime)s). End time: \(selectedTime)")
            throw SchedulingError.insufficientTime
        }

        logger.info("Starting schedule generation for '\(routine.name ?? "Unnamed")' with \(Int(availableTime / 60)) mins available.")
        let scheduler = CoreDataTaskScheduler(context: viewContext)

        let schedule = try scheduler.generateSchedule(for: routine, availableTime: availableTime)

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

                DispatchQueue.main.async {
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

                DispatchQueue.main.async {
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
                    self.logger.error("SchedulingError during schedule preview generation: \(error.localizedDescription)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.logger.error("Unexpected error during schedule preview generation: \(error.localizedDescription)")
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
