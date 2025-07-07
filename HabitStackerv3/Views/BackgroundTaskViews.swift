import SwiftUI

// MARK: - Background Tasks Bar
struct BackgroundTasksBar: View {
    @ObservedObject var runner: RoutineRunner
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(runner.backgroundTasks.indices, id: \.self) { index in
                    BackgroundTaskPill(
                        task: runner.backgroundTasks[index],
                        onTap: {
                            runner.switchBackgroundTaskToForeground(at: index)
                        },
                        onComplete: {
                            runner.completeBackgroundTask(at: index)
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            Color(.systemBackground)
                .opacity(0.95)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 2)
        )
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
        HStack(spacing: 6) {
            // Task name and time
            VStack(alignment: .leading, spacing: 1) {
                Text(task.task.taskName ?? "Unnamed")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(remainingTimeString)
                    .font(.caption2)
                    .foregroundColor(task.remainingTime <= 0 ? .red : .secondary)
                    .fontWeight(task.remainingTime <= 0 ? .bold : .regular)
            }
            
            // Complete button
            Button {
                onComplete()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .onTapGesture {
            onTap()
        }
    }
}

