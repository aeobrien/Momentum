import SwiftUI
import CoreData
import OSLog

struct SpendOverUnderView: View {
    @ObservedObject var runner: RoutineRunner
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTasks: Set<NSManagedObjectID> = []
    @State private var totalSelectedDuration: TimeInterval = 0
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SpendOverUnderView")
    
    private var availableTime: TimeInterval {
        max(0, -runner.scheduleOffset)
    }
    
    private var affordableTasks: [(task: CDTask, originalOrder: Int32, duration: TimeInterval)] {
        runner.getAffordableUnscheduledTasks()
    }
    
    private var timeFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header showing available time
                VStack(spacing: 8) {
                    Text("Available Time to Spend")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundColor(.yellow)
                        Text(timeFormatter.string(from: availableTime) ?? "0:00")
                            .font(.title2)
                            .fontWeight(.bold)
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
                
                if affordableTasks.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No tasks available within your time budget")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    List {
                        Section {
                            Text("Select tasks to add to your routine:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                        
                        ForEach(affordableTasks, id: \.task.objectID) { taskInfo in
                            TaskSelectionRow(
                                task: taskInfo.task,
                                duration: taskInfo.duration,
                                isSelected: selectedTasks.contains(taskInfo.task.objectID),
                                availableTime: availableTime - totalSelectedDuration,
                                onToggle: { toggleTask(taskInfo) }
                            )
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    
                    // Bottom section with summary
                    VStack(spacing: 12) {
                        Divider()
                        
                        HStack {
                            Text("Selected:")
                            Spacer()
                            Text(timeFormatter.string(from: totalSelectedDuration) ?? "0:00")
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Text("Remaining:")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "bitcoinsign.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                Text(timeFormatter.string(from: availableTime - totalSelectedDuration) ?? "0:00")
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        Button {
                            addSelectedTasks()
                        } label: {
                            Text("Add \(selectedTasks.count) Task\(selectedTasks.count == 1 ? "" : "s")")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedTasks.isEmpty ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(selectedTasks.isEmpty)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Spend Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func toggleTask(_ taskInfo: (task: CDTask, originalOrder: Int32, duration: TimeInterval)) {
        if selectedTasks.contains(taskInfo.task.objectID) {
            selectedTasks.remove(taskInfo.task.objectID)
            totalSelectedDuration -= taskInfo.duration
        } else {
            // Check if adding this task would exceed available time
            if totalSelectedDuration + taskInfo.duration <= availableTime {
                selectedTasks.insert(taskInfo.task.objectID)
                totalSelectedDuration += taskInfo.duration
            }
        }
    }
    
    private func addSelectedTasks() {
        let tasksToAdd = affordableTasks
            .filter { selectedTasks.contains($0.task.objectID) }
            .map { (task: $0.task, originalOrder: $0.originalOrder) }
        
        runner.addUnscheduledTasks(tasksToAdd)
        logger.info("Added \(tasksToAdd.count) tasks to schedule")
        
        dismiss()
    }
}

struct TaskSelectionRow: View {
    let task: CDTask
    let duration: TimeInterval
    let isSelected: Bool
    let availableTime: TimeInterval
    let onToggle: () -> Void
    
    private var canAfford: Bool {
        isSelected || duration <= availableTime
    }
    
    private var timeFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.taskName ?? "Unnamed Task")
                        .font(.body)
                        .foregroundColor(canAfford ? .primary : .secondary)
                        .lineLimit(2)
                    
                    Text(timeFormatter.string(from: duration) ?? "\(Int(duration/60))m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else if canAfford {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red.opacity(0.5))
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canAfford)
    }
}

// Preview
struct SpendOverUnderView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock runner for preview
        let context = CoreDataStack.shared.viewContext
        let routine = CDRoutine(context: context)
        routine.name = "Test Routine"
        
        let runner = RoutineRunner(
            context: context,
            routine: routine,
            schedule: [],
            originalFinishingTime: Date()
        )
        
        return SpendOverUnderView(runner: runner)
            .environment(\.managedObjectContext, context)
    }
}