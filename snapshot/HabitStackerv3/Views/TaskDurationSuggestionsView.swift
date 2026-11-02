import SwiftUI
import CoreData

struct TaskDurationSuggestionsView: View {
    let suggestions: [TaskDurationSuggestion]
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let logger = AppLogger.create(subsystem: "com.app.TaskDurationSuggestionsView", category: "UI")
    
    var body: some View {
        NavigationView {
            VStack {
                if suggestions.isEmpty {
                    Spacer()
                    Text("No duration suggestions at this time")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List {
                        Section {
                            Text("Based on your completion history, these tasks might benefit from duration adjustments:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
                        
                        ForEach(suggestions, id: \.task.objectID) { suggestion in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(suggestion.task.taskName ?? "Unnamed Task")
                                    .font(.headline)
                                
                                Text(suggestion.changeDescription)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("Based on \(suggestion.completionCount) completions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Update Duration") {
                                        updateTaskDuration(suggestion)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Duration Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Duration Updated", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func updateTaskDuration(_ suggestion: TaskDurationSuggestion) {
        logger.info("Updating duration for task '\(suggestion.task.taskName ?? "Unnamed")' from \(suggestion.currentDuration) to \(suggestion.suggestedDuration) minutes")
        
        // Update both min and max duration
        suggestion.task.minDuration = Int32(suggestion.suggestedDuration)
        suggestion.task.maxDuration = Int32(suggestion.suggestedDuration)
        
        // Save context
        do {
            try viewContext.save()
            alertMessage = "Updated '\(suggestion.task.taskName ?? "Task")' duration to \(suggestion.suggestedDuration) minutes"
            showingAlert = true
            logger.info("Successfully updated task duration")
        } catch {
            logger.error("Failed to save task duration update: \(error)")
            alertMessage = "Failed to update task duration"
            showingAlert = true
        }
    }
}