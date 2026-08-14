import SwiftUI
import WidgetKit
import ActivityKit

// Custom timer view that can show negative times
struct TimerView: View {
    let endTime: Date
    let isOverrun: Bool
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let difference = endTime.timeIntervalSince(now)
            
            if difference > 0 {
                // Counting down
                Text(timerInterval: now...endTime, countsDown: true)
                    .monospacedDigit()
                    .foregroundColor(.primary)
            } else {
                // Overrun - show negative time
                let absoluteDifference = abs(difference)
                let minutes = Int(absoluteDifference) / 60
                let seconds = Int(absoluteDifference) % 60
                
                Text(String(format: "-%d:%02d", minutes, seconds))
                    .monospacedDigit()
                    .foregroundColor(.red)
            }
        }
    }
}

struct RoutineLiveActivityView: View {
    let context: ActivityViewContext<RoutineActivityAttributes>
    
    var body: some View {
        // Simplified for debugging
        Text("Task: \(context.state.taskName)")
            .padding()
    }
    
    private var scheduleColor: Color {
        if context.state.scheduleOffsetString.contains("ahead") {
            return .green
        } else if context.state.scheduleOffsetString.contains("behind") {
            return .red
        } else {
            return .secondary
        }
    }
}

// Compact view for Dynamic Island
struct RoutineCompactActivityView: View {
    let context: ActivityViewContext<RoutineActivityAttributes>
    
    var body: some View {
        HStack {
            Image(systemName: context.state.isOverrun ? "exclamationmark.circle.fill" : "timer")
                .foregroundColor(context.state.isOverrun ? .red : .cyan)
            
            OverrunAwareTimer(end: context.state.taskEndTime)
        }
    }
}

// Minimal view for Dynamic Island
struct RoutineMinimalActivityView: View {
    let context: ActivityViewContext<RoutineActivityAttributes>
    
    var body: some View {
        Image(systemName: context.state.isOverrun ? "exclamationmark.circle.fill" : "timer")
            .foregroundColor(context.state.isOverrun ? .red : .cyan)
    }
}

// Expanded view for Dynamic Island
struct RoutineExpandedActivityView: View {
    let context: ActivityViewContext<RoutineActivityAttributes>
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.routineName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(context.state.taskName)
                    .font(.headline)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    // No lineLimit - let it use available space
                
                HStack(spacing: 12) {
                    // Timer
                    Label {
                        OverrunAwareTimer(end: context.state.taskEndTime)
                    } icon: {
                        Image(systemName: context.state.isOverrun ? "exclamationmark.circle.fill" : "timer")
                            .foregroundColor(context.state.isOverrun ? .red : .cyan)
                    }
                    
                    // Schedule status
                    Text(context.state.scheduleOffsetString)
                        .font(.caption)
                        .foregroundColor(scheduleColor)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var scheduleColor: Color {
        if context.state.scheduleOffsetString.contains("ahead") {
            return .green
        } else if context.state.scheduleOffsetString.contains("behind") {
            return .red
        } else {
            return .secondary
        }
    }
}
