import SwiftUI

struct RoutineSchedulerView: View {
    @StateObject private var taskManager = CustomTaskManager(selectedRoutine: "morning")
    @State private var selectedRoutine: String
    @State private var selectedEndTime: Date
    @State private var scheduledTasks: [CustomTask] = []
    @State private var totalScheduledTime: TimeInterval = 0
    @State private var showTaskSelection = true
    @State private var currentTaskIndex = 0
    @State private var showRoutineRunner = false
    @State private var userChangedTime = false
    @State private var programmaticChange = false
    @State private var forceRefresh = false // New state to force view refresh
    
    // **Add availableTime State**
        @State private var availableTime: TimeInterval?

    init() {
        let currentHour = Calendar.current.component(.hour, from: Date())
        switch currentHour {
        case 4..<11:
            _selectedRoutine = State(initialValue: "morning")
            _selectedEndTime = State(initialValue: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!)
        case 11..<18:
            _selectedRoutine = State(initialValue: "lunchtime")
            _selectedEndTime = State(initialValue: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!)
        default:
            _selectedRoutine = State(initialValue: "evening")
            _selectedEndTime = State(initialValue: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!)
        }
    }


    var body: some View {
        NavigationView {
            VStack {
                Picker("Select Routine", selection: $selectedRoutine) {
                    Text("Morning").tag("morning")
                    Text("Lunchtime").tag("lunchtime")
                    Text("Evening").tag("evening")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: selectedRoutine) { newRoutine in
                    if !userChangedTime {
                        programmaticChange = true
                        updateDefaultEndTime(for: newRoutine)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            programmaticChange = false
                            forceRefresh.toggle() // Force view refresh
                        }
                    }
                }

                if showTaskSelection {
                    DatePicker("Select End Time", selection: $selectedEndTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(WheelDatePickerStyle())
                        .labelsHidden()
                        .padding()
                        .id(forceRefresh) // Force view refresh by changing ID
                        .onChange(of: selectedEndTime) { _ in
                            if !programmaticChange {
                                userChangedTime = true
                            }
                        }

                    Button(action: scheduleTasks) {
                        Text("Schedule Tasks")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .shadow(radius: 10)
                    }
                    .padding()
                }

                if !scheduledTasks.isEmpty {
                    Text("Total Available Time: \(formattedTaskDuration(selectedEndTime.timeIntervalSince(Date()) - 1200))") // Display available time
                        .font(.headline)
                        .padding()

                    Text("Total Scheduled Time: \(formattedTaskDuration(totalScheduledTime))")
                        .font(.headline)
                        .padding()

                    List(scheduledTasks) { task in
                        HStack {
                            Text(task.taskName)  // Use taskName instead of task
                                .font(.headline)
                            Spacer()
                            Text(formattedTaskDuration(TimeInterval(task.minDuration)))  // Use minDuration
                                .font(.subheadline)
                        }
                    }
                    .listStyle(PlainListStyle())
                }

                Spacer()

                if !scheduledTasks.isEmpty {
                    HStack(spacing: 10) {
                        Button(action: {
                            scheduledTasks.removeAll()
                            totalScheduledTime = 0
                            showTaskSelection = true
                        }) {
                            Text("Reschedule")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                                .shadow(radius: 10)
                        }

                        Button(action: {
                            currentTaskIndex = 0
                            showRoutineRunner = true
                        }) {
                            Text("Start")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                                .shadow(radius: 10)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
            .padding()
            .sheet(isPresented: $showRoutineRunner) {
                // Safely unwrap availableTime or provide a default value
                RoutineRunnerView(
                    tasks: $scheduledTasks,
                    showRoutineRunner: $showRoutineRunner,
                    availableTime: availableTime ?? 0
                )
            }


        }
    }

    func updateDefaultEndTime(for routine: String) {
        switch routine {
        case "morning":
            selectedEndTime = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        case "lunchtime":
            selectedEndTime = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        case "evening":
            selectedEndTime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        default:
            break
        }
    }

    func scheduleTasks() {
        print("Scheduling tasks for routine: \(selectedRoutine)")
        let calculatedAvailableTime = selectedEndTime.timeIntervalSince(Date()) - 1200 // 20 minutes buffer
        
        // Assign to the @State variable
        self.availableTime = calculatedAvailableTime
        
        var remainingTime = calculatedAvailableTime
        var tasksToSchedule: [CustomTask] = []
        
        let routineTasks = taskManager.tasks
        
        for task in routineTasks.sorted(by: { $0.essentiality ?? 0 < $1.essentiality ?? 0 }) {
            let includeTask = true  // Assume all tasks are to be included
        
            if includeTask && TimeInterval(task.minDuration) <= remainingTime {
                tasksToSchedule.append(task)
                remainingTime -= TimeInterval(task.minDuration)
                print("Scheduled task \(task.taskName) with last completion at \(task.lastCompleted ?? "Never")")
            } else {
                print("Skipped task \(task.taskName) with last completion at \(task.lastCompleted ?? "Never")")
            }
        }
        
        scheduledTasks = tasksToSchedule
        totalScheduledTime = scheduledTasks.reduce(0) { $0 + TimeInterval($1.minDuration) }
        showTaskSelection = false
        print("Scheduled tasks: \(scheduledTasks)")
    }


    func convertStringToDate(_ string: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter.date(from: string)
    }

    func formattedTaskDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes) minute" + (minutes > 1 ? "s" : "")
        } else {
            return "\(seconds) second" + (seconds > 1 ? "s" : "")
        }
    }
}
