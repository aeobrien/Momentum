import SwiftUI

struct TempRoutineDetailView: View {
    @ObservedObject var runner: TempRoutineRunner
    @State private var editMode: EditMode = .active
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Temporary Routine")
                .font(.largeTitle)
                .padding(.bottom, 5)
            
            HStack {
                Text("Schedule Status:")
                    .font(.headline)
                Text(runner.scheduleOffsetString)
                    .font(.headline)
                    .foregroundColor(scheduleColor())
            }
            
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
            
            HStack {
                Text("Tasks (\(runner.currentTaskIndex + 1)/\(runner.tasks.count))")
                    .font(.headline)
                Spacer()
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 5)
            
            List {
                ForEach(Array(runner.tasks.enumerated()), id: \.element.id) { index, task in
                    HStack {
                        Image(systemName: taskStatusIcon(index: index))
                            .foregroundColor(taskStatusColor(index: index))
                            .frame(width: 25, alignment: .center)
                        
                        Text(task.name)
                            .foregroundColor(index <= runner.currentTaskIndex ? .secondary : .primary)
                        
                        Spacer()
                        
                        Text("\(task.duration) min")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .deleteDisabled(index <= runner.currentTaskIndex)
                    .moveDisabled(index <= runner.currentTaskIndex)
                }
                .onMove(perform: moveTask)
            }
            .listStyle(PlainListStyle())
            .environment(\.editMode, $editMode)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Routine Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func taskStatusIcon(index: Int) -> String {
        if runner.isRoutineComplete || index < runner.currentTaskIndex {
            return "checkmark.circle.fill"
        } else if index == runner.currentTaskIndex {
            return runner.isRunning ? "play.circle.fill" : "pause.circle.fill"
        } else {
            return "circle"
        }
    }
    
    private func taskStatusColor(index: Int) -> Color {
        if runner.isRoutineComplete || index < runner.currentTaskIndex {
            return .green
        } else if index == runner.currentTaskIndex {
            return runner.isRunning ? .blue : .orange
        } else {
            return .gray
        }
    }
    
    private func scheduleColor() -> Color {
        if runner.scheduleOffsetString == "On schedule" {
            return .secondary
        } else if runner.scheduleOffsetString.contains("ahead") {
            return .green
        } else if runner.scheduleOffsetString.contains("behind") {
            return .red
        } else {
            return .primary
        }
    }
    
    private func moveTask(from source: IndexSet, to destination: Int) {
        runner.reorderTasks(from: source, to: destination)
    }
}