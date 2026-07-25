import ActivityKit
import SwiftUI
import WidgetKit

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

@available(iOS 16.2, *)
struct RoutineLiveActivity: Widget {
    
    // Use a *separate* font for compact; keep it fixed so name & timer match
    private let compactFont: Font = .system(size: 12, weight: .regular)
        private let expandedFont: Font = .system(size: 17, weight: .semibold)
    
    var body: some WidgetConfiguration {
        

        ActivityConfiguration(for: RoutineActivityAttributes.self) { context in
            // Lock screen presentation - Empty view to hide it
            EmptyView()
        } // Inside ActivityConfiguration(attributes:contentState:content:)
        dynamicIsland: { context in
                    DynamicIsland {
                        // -------- Expanded --------
                        DynamicIslandExpandedRegion(.center) {
                            VStack(spacing: 4) {
                                Text(context.state.taskName)
                                    .font(expandedFont)
                                    .multilineTextAlignment(.center)

                                OverrunAwareTimer(end: context.state.taskEndTime)
                                    .font(expandedFont.monospacedDigit())
                                    .foregroundColor(context.state.isOverrun ? .red : .primary)
                            }
                        }

                        DynamicIslandExpandedRegion(.bottom) {
                            if !context.state.scheduleOffsetString.isEmpty {
                                Text(context.state.scheduleOffsetString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } compactLeading: {
                        Text(context.state.taskName)
                            .font(compactFont)
                            .truncationMode(.tail)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } compactTrailing: {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: 8)
                            OverrunAwareTimer(end: context.state.taskEndTime)
                                .font(compactFont.monospacedDigit())
                                .lineLimit(1)
                                .foregroundColor(context.state.isOverrun ? .red : .primary)
                        }
                    } minimal: {
                        Image(systemName: context.state.isOverrun ? "exclamationmark.triangle.fill" : "timer")
                    }
                }

    }
}

