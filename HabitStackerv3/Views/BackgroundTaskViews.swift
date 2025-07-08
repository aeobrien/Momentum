import SwiftUI

// MARK: - Background Tasks Bar
struct BackgroundTasksBar: View {
    @ObservedObject var runner: RoutineRunner
    
    var body: some View {
        if let firstTask = runner.backgroundTasks.first {
            BackgroundTaskPill(
                task: firstTask,
                onTap: {
                    runner.switchBackgroundTaskToForeground(at: 0)
                },
                onComplete: {
                    runner.completeBackgroundTask(at: 0)
                }
            )
            .padding(.horizontal, 50) // Padding to stay between X and info buttons
        }
    }
}

// MARK: - Background Task Pill
struct BackgroundTaskPill: View {
    let task: BackgroundTaskState
    let onTap: () -> Void
    let onComplete: () -> Void
    
    private var remainingTimeString: String {
        let minutes = Int(task.remainingTime) / 60
        let seconds = Int(task.remainingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Task name
            Text(task.task.taskName ?? "Unnamed")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .layoutPriority(1)
            
            // Time remaining
            Text(remainingTimeString)
                .font(.caption)
                .foregroundColor(task.remainingTime <= 0 ? .red : .white.opacity(0.8))
                .fontWeight(task.remainingTime <= 0 ? .bold : .regular)
                .monospacedDigit()
            
            // Complete button
            Button {
                onComplete()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 30) // Same height as top bar buttons
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
        )
        .onTapGesture {
            onTap()
        }
    }
}