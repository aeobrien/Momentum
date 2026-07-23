//
//  ChecklistTaskView.swift
//  Momentum
//
//  Created on 28/07/2025.
//

import SwiftUI
import CoreData

struct ChecklistTaskView: View {
    @ObservedObject var runner: RoutineRunner
    @State private var checklistItems: [ChecklistItem] = []
    @State private var showingCompletionAnimation = false
    
    private var currentTask: CDTask? {
        guard runner.currentTaskIndex >= 0 && runner.currentTaskIndex < runner.scheduledTasks.count else {
            return nil
        }
        return runner.scheduledTasks[runner.currentTaskIndex].task
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Top bar with next task on left, timer on right
            HStack(alignment: .top) {
                // Next task and schedule info on the left
                VStack(alignment: .leading, spacing: 4) {
                    // Next task on one line
                    Text("Next: \(runner.nextTaskName ?? "Last task")")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Schedule status and estimated finish time
                    HStack(spacing: 6) {
                        Text(runner.scheduleOffsetString)
                            .font(.caption2)
                            .foregroundColor(scheduleColor())
                            .fontWeight(.medium)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(runner.estimatedFinishingTimeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Timer with thin circular progress bars on the right
                ZStack {
                    // Custom thin progress rings
                    // Outer ring background
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // Outer ring progress (routine)
                    Circle()
                        .trim(from: 0.0, to: runner.progressFraction)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 80, height: 80)
                    
                    // Inner ring background
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 65, height: 65)
                    
                    // Inner ring progress (task)
                    Circle()
                        .trim(from: 0.0, to: runner.taskProgressFraction)
                        .stroke(runner.isOverrun ? Color.red : Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 65, height: 65)
                    
                    // Timer display
                    Text(runner.remainingTimeString)
                        .font(.system(size: 20, weight: .medium).monospacedDigit())
                        .foregroundColor(runner.isRunning ? (runner.isOverrun ? .red : .blue) : .gray)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            
            Divider()
                .padding(.horizontal)
            
            // Checklist items (expanded to use maximum space)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(checklistItems.sorted(by: { $0.order < $1.order })) { item in
                        ChecklistItemRow(
                            item: item,
                            onToggle: { toggleItem(item) }
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
                .padding(.horizontal)
            }
            .frame(minHeight: 250) // Set minimum height to show more items without overlapping bottom navigation
            
            // Completion status
            let completedCount = checklistItems.filter { $0.isCompleted }.count
            let totalCount = checklistItems.count
            
            if totalCount > 0 {
                VStack(spacing: 8) {
                    // Progress indicator
                    HStack {
                        Text("\(completedCount) of \(totalCount) completed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Progress circle
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(completedCount) / CGFloat(totalCount))
                                .stroke(
                                    completedCount == totalCount ? Color.green : Color.blue,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: completedCount)
                        }
                        .frame(width: 30, height: 30)
                    }
                    .padding(.horizontal)
                    
                    // Auto-complete message
                    if completedCount == totalCount && !showingCompletionAnimation {
                        Text("All items completed! Task will complete automatically...")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal)
                            .onAppear {
                                completeTask()
                            }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
            }
        }
        .onAppear {
            loadChecklistItems()
        }
    }
    
    private func scheduleColor() -> Color {
        if runner.scheduleOffsetString.contains("ahead") {
            return Color(red: 0, green: 0.7, blue: 0)
        } else if runner.scheduleOffsetString.contains("behind") {
            return Color(red: 0.8, green: 0, blue: 0)
        } else {
            return .secondary
        }
    }
    
    private func loadChecklistItems() {
        guard let task = currentTask,
              let items = task.checklistItems as? [ChecklistItem] else {
            return
        }

        // Get existing completion states for this task
        let existingStates = runner.checklistCompletionStates[runner.currentTaskIndex] ?? [:]

        // Create mutable copies of the items, preserving completion state if it exists
        checklistItems = items.map { item in
            ChecklistItem(
                id: item.id,
                title: item.title,
                isCompleted: existingStates[item.id] ?? false, // Use persisted state or default to false
                order: item.order
            )
        }
    }
    
    private func toggleItem(_ item: ChecklistItem) {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            checklistItems[index].isCompleted.toggle()
        }

        // Update the persisted state in RoutineRunner
        if runner.checklistCompletionStates[runner.currentTaskIndex] == nil {
            runner.checklistCompletionStates[runner.currentTaskIndex] = [:]
        }
        runner.checklistCompletionStates[runner.currentTaskIndex]?[item.id] = checklistItems[index].isCompleted

        // Check if all items are completed
        if checklistItems.allSatisfy({ $0.isCompleted }) && !showingCompletionAnimation {
            completeTask()
        }
    }
    
    private func completeTask() {
        showingCompletionAnimation = true
        
        // Delay briefly to show completion state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            runner.markTaskComplete()
        }
    }
}

struct ChecklistItemRow: View {
    let item: ChecklistItem
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.isCompleted ? .green : .gray)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isCompleted)
                
                Text(item.title)
                    .font(.body)
                    .foregroundColor(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .animation(.easeInOut(duration: 0.2), value: item.isCompleted)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.isCompleted ? Color.gray.opacity(0.1) : Color.blue.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(item.isCompleted ? Color.clear : Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ChecklistTaskView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock runner for preview
        let context = CoreDataStack.shared.viewContext
        let routine = CDRoutine(context: context)
        routine.name = "Test Routine"
        
        let task = CDTask(context: context)
        task.taskName = "Morning Checklist"
        task.isChecklistTask = true
        task.checklistItems = [
            ChecklistItem(title: "Brush teeth", order: 0),
            ChecklistItem(title: "Make bed", order: 1),
            ChecklistItem(title: "Drink water", order: 2),
            ChecklistItem(title: "Take vitamins", order: 3)
        ] as NSObject
        
        let scheduledTask = ScheduledTask(task: task, allocatedDuration: 300)
        let runner = RoutineRunner(context: context, routine: routine, schedule: [scheduledTask])
        
        return ChecklistTaskView(runner: runner)
            .previewLayout(.sizeThatFits)
    }
}