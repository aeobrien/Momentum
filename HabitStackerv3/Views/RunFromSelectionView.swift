import SwiftUI
import CoreData

struct RunFromSelectionView: View {
    let routine: CDRoutine
    @Binding var selectedStartIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [CDTask] = []
    
    private let logger = AppLogger.create(subsystem: "com.app.RunFromSelectionView", category: "UI")
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Select where to start the routine from:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                
                List {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                        Button(action: {
                            selectedStartIndex = index
                            dismiss()
                        }) {
                            HStack {
                                Text("\(index + 1).")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .leading)
                                
                                Text(task.taskName ?? "Unnamed Task")
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if index == 0 {
                                    Text("(Start)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Run From")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadTasks()
        }
    }
    
    private func loadTasks() {
        // Get ordered tasks from the routine
        if let routineTasks = routine.taskRelations as? Set<CDRoutineTask> {
            let sortedRoutineTasks = routineTasks.sorted { $0.order < $1.order }
            tasks = sortedRoutineTasks.compactMap { $0.task }
            logger.info("Loaded \(tasks.count) tasks for 'run from' selection")
        }
    }
}