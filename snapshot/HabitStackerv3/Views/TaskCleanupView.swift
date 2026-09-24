import SwiftUI
import CoreData

struct TaskCleanupView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTask.taskName, ascending: true)],
        animation: .default
    ) private var allTasks: FetchedResults<CDTask>

    @State private var tasksToDelete: Set<CDTask> = []
    @State private var showDeleteConfirmation = false

    private let logger = AppLogger.create(subsystem: "com.app.TaskCleanupView", category: "UI")

    // Calculate the multiplier based on repetition interval
    private func getMultiplier(for intervalSeconds: Int32) -> Double {
        let days = Double(intervalSeconds) / 86400.0

        if days >= 90 { // 3 months or longer
            return 2.5
        } else if days <= 1 { // 1 day or less
            return 21.0
        } else {
            // Gradient calculation: interpolate between 21 (1 day) and 2.5 (90 days)
            let ratio = (days - 1) / (90 - 1)
            return 21.0 - (ratio * (21.0 - 2.5))
        }
    }

    // Check if a task is overdue based on its repetition interval
    private func isOverdue(_ task: CDTask) -> Bool {
        guard task.repetitionInterval > 0,
              let lastCompleted = task.lastCompleted else {
            return false
        }

        let multiplier = getMultiplier(for: task.repetitionInterval)
        let overdueCutoff = TimeInterval(task.repetitionInterval) * multiplier
        let timeSinceCompletion = Date().timeIntervalSince(lastCompleted)

        return timeSinceCompletion > overdueCutoff
    }

    // Check if a task is orphaned (not part of any routine)
    private func isOrphaned(_ task: CDTask) -> Bool {
        guard let relations = task.routineRelations else { return true }
        return relations.count == 0
    }

    // Group tasks for display
    private var overdueTasks: [CDTask] {
        allTasks.filter { isOverdue($0) }
    }

    private var orphanedTasks: [CDTask] {
        allTasks.filter { isOrphaned($0) }
    }

    private var suggestedTasks: [CDTask] {
        Array(Set(overdueTasks + orphanedTasks))
            .sorted { ($0.taskName ?? "") < ($1.taskName ?? "") }
    }

    private func formatTimeSince(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)

        if days >= 30 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else if days >= 7 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if days == 0 {
            return "Today"
        } else {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if suggestedTasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("All tasks are up to date!")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("No tasks need cleanup at this time")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        Section(header:
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SUGGESTED FOR CLEANUP")
                                Text("These tasks are either overdue or not part of any routines")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        ) {
                            ForEach(suggestedTasks, id: \.objectID) { task in
                                HStack {
                                    Button(action: {
                                        if tasksToDelete.contains(task) {
                                            tasksToDelete.remove(task)
                                        } else {
                                            tasksToDelete.insert(task)
                                        }
                                    }) {
                                        Image(systemName: tasksToDelete.contains(task) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(tasksToDelete.contains(task) ? .red : .gray)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.taskName ?? "Unnamed Task")
                                            .font(.headline)

                                        HStack(spacing: 12) {
                                            if isOrphaned(task) {
                                                Label("No routines", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }

                                            if isOverdue(task), let lastCompleted = task.lastCompleted {
                                                Label(formatTimeSince(lastCompleted), systemImage: "clock.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if !tasksToDelete.isEmpty {
                            Section {
                                Text("\(tasksToDelete.count) task\(tasksToDelete.count == 1 ? "" : "s") selected for deletion")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Task Cleanup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !tasksToDelete.isEmpty {
                        Button("Delete") {
                            showDeleteConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("Delete Tasks", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTasks()
                }
            } message: {
                Text("Are you sure you want to delete \(tasksToDelete.count) task\(tasksToDelete.count == 1 ? "" : "s")? This action cannot be undone.")
            }
        }
    }

    private func deleteTasks() {
        for task in tasksToDelete {
            // Remove all routine relationships first
            if let relations = task.routineRelations?.allObjects as? [CDRoutineTask] {
                for relation in relations {
                    viewContext.delete(relation)
                }
            }
            viewContext.delete(task)
        }

        do {
            try viewContext.save()
            logger.info("Deleted \(tasksToDelete.count) tasks during cleanup")
            dismiss()
        } catch {
            logger.error("Failed to delete tasks during cleanup", error: error)
        }
    }
}