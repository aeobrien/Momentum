import SwiftUI

// MARK: - Reorderable Task Item
struct ReorderableTaskItem: Identifiable {
    let id = UUID()
    let name: String
    let duration: Int
    let isCustom: Bool
    let originalTemplate: DefaultTaskTemplate?
    let originalCustomEntry: RoutineBuilder.CustomTaskEntry?
}

// MARK: - Enhanced Confirmation View with Reordering
struct ReorderableConfirmationView: View {
    let routineName: String
    @State private var orderedTasks: [ReorderableTaskItem]
    let onConfirm: ([ReorderableTaskItem]) -> Void
    let onBack: () -> Void
    
    init(routineName: String,
         selectedTasks: [DefaultTaskTemplate],
         customTasks: [RoutineBuilder.CustomTaskEntry],
         onConfirm: @escaping ([ReorderableTaskItem]) -> Void,
         onBack: @escaping () -> Void) {
        self.routineName = routineName
        self.onConfirm = onConfirm
        self.onBack = onBack
        
        // Initialize ordered tasks
        var tasks: [ReorderableTaskItem] = []
        
        // Add template tasks
        for template in selectedTasks {
            tasks.append(ReorderableTaskItem(
                name: template.name,
                duration: template.suggestedDuration,
                isCustom: false,
                originalTemplate: template,
                originalCustomEntry: nil
            ))
        }
        
        // Add custom tasks
        for custom in customTasks where !custom.name.isEmpty {
            tasks.append(ReorderableTaskItem(
                name: custom.name,
                duration: custom.duration,
                isCustom: true,
                originalTemplate: nil,
                originalCustomEntry: custom
            ))
        }
        
        self._orderedTasks = State(initialValue: tasks)
    }
    
    var totalDuration: Int {
        orderedTasks.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Confirm Routine")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Review and reorder your tasks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Routine summary
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(routineName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    Label("\(orderedTasks.count) tasks", systemImage: "checkmark.circle")
                    Label("\(totalDuration) min", systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Reorderable task list
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Drag to reorder tasks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    EditButton()
                        .font(.caption)
                }
                .padding(.horizontal)
                
                List {
                    ForEach(orderedTasks) { task in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.gray)
                                .font(.caption)
                            
                            Text(task.name)
                                .font(.body)
                            
                            Spacer()
                            
                            if task.isCustom {
                                Text("Custom")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                            
                            Text("\(task.duration) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveTask)
                    .onDelete(perform: deleteTask)
                }
                .listStyle(InsetGroupedListStyle())
            }
            
            // Action buttons
            HStack {
                Button(action: onBack) {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    onConfirm(orderedTasks)
                }) {
                    Text("Create Routine")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(orderedTasks.isEmpty ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(orderedTasks.isEmpty)
            }
            .padding()
        }
    }
    
    private func moveTask(from source: IndexSet, to destination: Int) {
        orderedTasks.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deleteTask(at offsets: IndexSet) {
        orderedTasks.remove(atOffsets: offsets)
    }
}