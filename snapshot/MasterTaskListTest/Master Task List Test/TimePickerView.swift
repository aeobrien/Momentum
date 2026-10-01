import SwiftUI

struct TimePickerView: View {
    @State private var selectedTime: Date = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State var availableTime: TimeInterval?
    @State private var navigateToPriorityView = false
    @State private var navigateToTaskListView = false
    @State private var essentialTasksTime: TimeInterval = 0
    @State private var essentialAndCoreTasksTime: TimeInterval = 0
    @State private var allTasksTime: TimeInterval = 0
    @State private var tasks: [CustomTask] = []
    @State private var selectedRoutine: String = "morning"
    @State private var currentTime: Date = Date()
    @State private var routines: [String] = []
    @State private var showPlaylistManager = false
    @State private var refreshTrigger = false

    @ObservedObject var taskManager: CustomTaskManager
    
    @Environment(\.colorScheme) var colorScheme

    init() {
        let defaultRoutine = "morning"
        _taskManager = ObservedObject(wrappedValue: CustomTaskManager(selectedRoutine: defaultRoutine))
    }

    var body: some View {
        NavigationView {
            ZStack {
                backgroundLayer
                
                VStack(spacing: 25) {
                    playlistPicker
                    timeSelectionSection
                    timeSummarySection
                    Spacer()
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
            .navigationTitle("Routine Planner")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accentColor(accentColor)
        .sheet(isPresented: $showPlaylistManager) {
            PlaylistManagerView(refreshTrigger: $refreshTrigger)
        }
        .onChange(of: refreshTrigger) { _ in
            loadRoutines()
            loadPlaylistAndCalculateTimes()
        }
        .onAppear {
            loadRoutines()
            loadPlaylistAndCalculateTimes()
            updateTimeDisplay()
        }
        .background(
            NavigationLink(destination: CustomTaskPriorityView(availableTime: availableTime ?? 0, selectedRoutine: selectedRoutine), isActive: $navigateToPriorityView) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: TaskListView(taskManager: taskManager), isActive: $navigateToTaskListView) {
                EmptyView()
            }
        )
    }
    
    private var backgroundLayer: some View {
        Color(colorScheme == .dark ? .black : .white)
            .overlay(
                Image(systemName: "clock")
                    .font(.system(size: 200))
                    .foregroundColor(Color(.systemGray6))
                    .offset(x: 100, y: -200)
                    .opacity(0.1)
            )
            .edgesIgnoringSafeArea(.all)
    }
    
    private var accentColor: Color {
        Color(#colorLiteral(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    }
    
    private var playlistPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Select Playlist", selection: $selectedRoutine) {
                ForEach(routines, id: \.self) { routine in
                    Text(routine.capitalized).tag(routine.lowercased())
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedRoutine) { newValue in
                taskManager.loadPlaylist(for: newValue)
                loadPlaylistAndCalculateTimes()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var timeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set End Time")
                .font(.headline)
                .foregroundColor(.secondary)
            
            DatePicker("End Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(WheelDatePickerStyle())
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .onChange(of: selectedTime) { _ in
                    updateTimeDisplay()
                }
        }
    }
    
    private var timeSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let availableTaskTime = availableTaskTime() {
                timeInfoView(label: availableTaskTime.label, time: availableTaskTime.time)
            } else {
                Text("Insufficient time for tasks")
                    .font(.title3)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
        }
    }
    
    private func timeInfoView(label: String, time: TimeInterval) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(formatTimeInterval(time))
                    .font(.title2)
                    .fontWeight(.medium)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 15) {
            actionButton(title: "All Tasks", systemImage: "square.and.pencil", action: {
                navigateToTaskListView = true
            })
            
            actionButton(title: "Run Routine", systemImage: "play.fill", action: {
                calculateAvailableTime()
                navigateToPriorityView = true
            })
            
            actionButton(title: "Edit Playlists", systemImage: "gear", action: {
                showPlaylistManager = true
            })
        }
    }
    
    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(accentColor)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
    
    private func availableTaskTime() -> (label: String, time: TimeInterval)? {
        print("⏰ Checking availableTaskTime")
        print("   Available: \(availableTime.map { $0/60 }?.description ?? "nil")m")
        print("   Essential: \(essentialTasksTime/60)m")
        print("   Essential+Core: \(essentialAndCoreTasksTime/60)m")
        print("   All: \(allTasksTime/60)m")
        
        guard let availableTime = availableTime else {
            print("⚠️ No available time calculated")
            return nil
        }
        
        if allTasksTime <= availableTime {
            print("✅ Returning all tasks time")
            return ("All Tasks", allTasksTime)
        } else if essentialAndCoreTasksTime <= availableTime {
            print("✅ Returning essential+core tasks time")
            return ("Essential + Core Tasks", essentialAndCoreTasksTime)
        } else if essentialTasksTime <= availableTime {
            print("✅ Returning essential tasks time")
            return ("Essential Tasks", essentialTasksTime)
        }
        
        print("⚠️ Insufficient time for any task group")
        return nil
    }
    
    private func loadRoutines() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bundleURL = Bundle.main.resourceURL!
        
        do {
            let documentFiles = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let bundleFiles = try fileManager.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
            
            let allFiles = documentFiles + bundleFiles
            
            routines = allFiles.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix("Routine.json") }
                .map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Routine", with: "") }
            
            if let firstRoutine = routines.first, !routines.map({ $0.lowercased() }).contains(selectedRoutine) {
                selectedRoutine = firstRoutine.lowercased()
                taskManager.loadPlaylist(for: selectedRoutine)
                loadPlaylistAndCalculateTimes()
            }
        } catch {
            print("Error while loading routines: \(error)")
        }
    }
    
    private func loadPlaylistAndCalculateTimes() {
        print("⏰ Starting loadPlaylistAndCalculateTimes")
        taskManager.loadPlaylist(for: selectedRoutine)
        fetchTasks()
        performInitialCalculations()
        print("⏰ Times calculated - Essential: \(essentialTasksTime/60)m, Core+Essential: \(essentialAndCoreTasksTime/60)m, All: \(allTasksTime/60)m")
    }
    
    private func fetchTasks() {
        print("⏰ Starting fetchTasks")
        tasks = taskManager.getFilteredTasks(currentTime: currentTime)
        print("⏰ Initial task count: \(tasks.count)")
        
        if let playlistUUIDs = taskManager.playlist?.taskUUIDs {
            print("⏰ Playlist UUIDs count: \(playlistUUIDs.count)")
            tasks.sort { task1, task2 in
                if let index1 = playlistUUIDs.firstIndex(of: task1.UUID),
                   let index2 = playlistUUIDs.firstIndex(of: task2.UUID) {
                    return index1 < index2
                }
                return false
            }
        } else {
            print("⚠️ No playlist UUIDs available")
        }
        
        print("⏰ Final sorted task count: \(tasks.count)")
        tasks.forEach { task in
            print("📋 Task: \(task.taskName), Duration: \(task.minDuration/60)m, Essentiality: \(task.essentiality ?? -1)")
        }
    }
    
    private func performInitialCalculations() {
        print("⏰ Starting performInitialCalculations with \(tasks.count) tasks")
        print("📊 Task breakdown:")
        tasks.forEach { task in
            print("  - \(task.taskName): Essentiality = \(task.essentiality ?? -1)")
        }
        
        let essentialTasks = tasks.filter { $0.essentiality == 3 }
        essentialTasksTime = essentialTasks.reduce(0) { $0 + TimeInterval($1.minDuration) }
        print("📊 Essential tasks (\(essentialTasks.count)): \(essentialTasksTime/60)m")
        
        let essentialAndCoreTasks = tasks.filter { $0.essentiality == 3 || $0.essentiality == 2 }
        essentialAndCoreTasksTime = essentialAndCoreTasks.reduce(0) { $0 + TimeInterval($1.minDuration) }
        print("📊 Essential+Core tasks (\(essentialAndCoreTasks.count)): \(essentialAndCoreTasksTime/60)m")
        
        allTasksTime = tasks.reduce(0) { sum, task in
            print("  Adding \(task.taskName): \(task.minDuration/60)m")
            return sum + TimeInterval(task.minDuration)
        }
        print("📊 All tasks: \(allTasksTime/60)m")
    }
    
    private func calculateAvailableTime() {
        print("⏰ Starting calculateAvailableTime")
        print("   Selected time: \(selectedTime)")
        print("   Current time: \(Date())")
        
        let currentTime = Date()
        if selectedTime <= currentTime {
            print("⏰ Selected time is in the past, calculating for next day")
            let calendar = Calendar.current
            let selectedTimeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
            if let selectedHour = selectedTimeComponents.hour,
               let selectedMinute = selectedTimeComponents.minute {
                var nextDayComponents = calendar.dateComponents([.year, .month, .day], from: currentTime)
                nextDayComponents.day! += 1
                nextDayComponents.hour = selectedHour
                nextDayComponents.minute = selectedMinute
                if let nextDayTime = calendar.date(from: nextDayComponents) {
                    availableTime = nextDayTime.timeIntervalSince(currentTime)
                    print("✅ Calculated next day available time: \(availableTime.map { $0/60 }?.description ?? "nil")m")
                }
            }
        } else {
            availableTime = selectedTime.timeIntervalSince(currentTime)
            print("✅ Calculated same day available time: \(availableTime.map { $0/60 }?.description ?? "nil")m")
        }
    }
    
    private func updateTimeDisplay() {
        calculateAvailableTime()
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}

struct PlaylistTasksView: View {
    let tasks: [CustomTask]
    
    var body: some View {
        List(tasks) { task in
            HStack {
                Text(task.taskName)
                Spacer()
                Text(formatDuration(task.minDuration))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Playlist Tasks")
    }
    
    private func formatDuration(_ duration: Int) -> String {
        let minutes = duration / 60
        return "\(minutes) min"
    }
}
