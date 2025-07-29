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
        VStack(spacing: 16) {
            // Minimal timer display with progress bars
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Time remaining
                    Text(runner.remainingTimeString)
                        .font(.system(size: 24, weight: .medium).monospacedDigit())
                        .foregroundColor(runner.isRunning ? (runner.isOverrun ? .red : .blue) : .gray)
                    
                    // Progress bars
                    VStack(spacing: 2) {
                        // Task progress
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 4)
                                
                                Rectangle()
                                    .fill(runner.isOverrun ? Color.red : Color.blue)
                                    .frame(width: geometry.size.width * runner.taskProgressFraction, height: 4)
                            }
                        }
                        .frame(height: 4)
                        
                        // Overall progress
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 4)
                                
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: geometry.size.width * runner.progressFraction, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                
                Spacer()
                
                // Schedule status
                VStack(alignment: .trailing, spacing: 4) {
                    Text(runner.scheduleOffsetString)
                        .font(.caption)
                        .foregroundColor(scheduleColor())
                        .fontWeight(.medium)
                    
                    if let nextTask = runner.nextTaskName {
                        Text("Next: \(nextTask)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Task name
            Text(currentTask?.taskName ?? "Checklist Task")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
            
            // Checklist items
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
                .padding(.vertical, 8)
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
        
        // Create mutable copies of the items
        checklistItems = items.map { item in
            ChecklistItem(
                id: item.id,
                title: item.title,
                isCompleted: false, // Reset completion state for this run
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