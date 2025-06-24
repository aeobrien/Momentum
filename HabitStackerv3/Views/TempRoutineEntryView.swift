import SwiftUI

struct TempRoutineEntryView: View {
    @State private var taskText: String = ""
    @State private var taskListForSheet: TempTaskList? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    private let logger = AppLogger.create(subsystem: "com.app.TempRoutineEntryView", category: "UI")
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Instructions
                Text("Enter tasks, one per line")
                    .font(.headline)
                    .padding(.top)
                
                // Text editor for task entry
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $taskText)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                        )
                    
                    // Placeholder text
                    if taskText.isEmpty {
                        Text("Example:\nMeditate\nExercise\nRead book\nPlan day")
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 200)
                .padding(.horizontal)
                
                // Submit button
                Button(action: submitTasks) {
                    Text("Next: Set Times")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(taskText.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(10)
                }
                .disabled(taskText.isEmpty)
                .padding(.horizontal)
                
                
                Spacer()
            }
            .navigationTitle("Temporary Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $taskListForSheet) { taskList in
                TempRoutineTimeAllocationView(taskNames: taskList.tasks)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    private func submitTasks() {
        // Parse tasks from text (split by newlines, filter empty lines)
        let tasks = taskText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        logger.info("Parsed \(tasks.count) tasks from temporary routine input")
        print("[TempRoutineEntryView] Parsed tasks: \(tasks)")
        
        if !tasks.isEmpty {
            // Create the task list wrapper for sheet presentation
            taskListForSheet = TempTaskList(tasks: tasks)
        }
    }
}

struct TempRoutineEntryView_Previews: PreviewProvider {
    static var previews: some View {
        TempRoutineEntryView()
    }
}