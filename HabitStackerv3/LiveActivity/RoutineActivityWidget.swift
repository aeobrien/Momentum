import WidgetKit
import SwiftUI
import ActivityKit

// This is just the configuration, not an actual widget
// Live Activities don't need @main or WidgetBundle
struct RoutineActivityConfiguration {
    static func configure() -> ActivityConfiguration<RoutineActivityAttributes> {
        return ActivityConfiguration(for: RoutineActivityAttributes.self) { context in
            // Lock screen / banner UI
            HStack {
                VStack(alignment: .leading) {
                    Text(context.attributes.routineName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(context.state.taskName)
                        .font(.headline)
                }
                Spacer()
                Text("Time")
                    .font(.title2)
            }
            .padding()
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.taskName)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.cyan)
            } compactTrailing: {
                Text("0:00")
                    .foregroundColor(.cyan)
                    .font(.caption)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundColor(.cyan)
            }
        }
    }
}