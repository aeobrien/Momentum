import SwiftUI
import CoreData

struct RoutineDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var cdRoutine: CDRoutine
    @ObservedObject var viewModel: RoutineViewModel
    @State private var showingEditRoutine = false
    
    private let logger = AppLogger.create(subsystem: "com.app.RoutineDetailView", category: "UI")
    
    private var formattedDuration: String {
        let totalMinutes = (cdRoutine.taskRelations?.allObjects as? [CDRoutineTask] ?? [])
            .compactMap { $0.task?.minDuration }
            .reduce(0) { $0 + Int($1) }
        
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(totalMinutes)m"
        }
    }
    
    private var orderedTasks: [CDTask] {
        let relations = cdRoutine.taskRelations?.allObjects as? [CDRoutineTask] ?? []
        return relations.sorted { $0.order < $1.order }
            .compactMap { $0.task }
    }
    
    private func removeTask(_ task: CDTask) {
        logger.debug("Removing task from routine: \(task.taskName ?? "")")
        
        guard let relation = (cdRoutine.taskRelations?.allObjects as? [CDRoutineTask])?.first(where: { $0.task == task }) else {
            logger.error("Could not find relation for task: \(task.taskName ?? "")")
            return
        }
        
        viewContext.delete(relation)
        
        do {
            try viewContext.save()
            logger.info("Successfully removed task: \(task.taskName ?? "")")
        } catch {
            logger.error("Failed to remove task", error: error)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Routine Overview Card
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cdRoutine.name ?? "")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("\(orderedTasks.count) tasks · \(formattedDuration)")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    // Stats Row
                    HStack(spacing: 20) {
                        StatBox(
                            title: "Completions",
                            value: "\(cdRoutine.totalCompletions)",
                            icon: "checkmark.circle.fill"
                        )
                        
                        StatBox(
                            title: "Last Used",
                            value: (cdRoutine.lastUsed ?? Date()).formatted(date: .abbreviated, time: .omitted),
                            icon: "clock.fill"
                        )
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 1)
                .padding(.horizontal)
                
                // Tasks List
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tasks")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(orderedTasks, id: \.self) { task in
                        TaskCard(cdTask: task, isSelected: false)
                            .padding(.horizontal)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeTask(task)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarItems(
                trailing: Button(action: {
                    logger.debug("Opening edit routine view")
                    showingEditRoutine = true
                }) {
                    Text("Edit")
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingEditRoutine) {
                NavigationView {
                    EditRoutineView(cdRoutine: cdRoutine)
                        .environment(\.managedObjectContext, viewContext)
                }
            }
        }
    }
    
    struct StatBox: View {
        let title: String
        let value: String
        let icon: String
        
        var body: some View {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }
}

struct RoutineDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = CoreDataStack.shared.viewContext
        let cdRoutine = CDRoutine(context: context)
        cdRoutine.uuid = UUID()
        cdRoutine.name = "Sample Routine"
        cdRoutine.createdOn = Date()
        cdRoutine.lastUsed = Date()
        cdRoutine.totalCompletions = 5
        cdRoutine.averageCompletionTime = 60
        
        return RoutineDetailView(
            cdRoutine: cdRoutine,
            viewModel: RoutineViewModel()
        )
        .environment(\.managedObjectContext, context)
    }
}
