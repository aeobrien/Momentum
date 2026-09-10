// OverrunAwareTimer.swift – full file
import SwiftUI

struct OverrunAwareTimer: View {
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = end.timeIntervalSince(context.date)

            if remaining > 0 {
                // Still counting down
                Text(timerInterval: context.date...end, countsDown: true)
                    .monospacedDigit()
            } else {
                // Overrun
                let secs = Int(-remaining)
                Text(String(format: "-%d:%02d", secs / 60, secs % 60))
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .accessibilityLabel(Text("Overrun by \(secs / 60) minutes \(secs % 60) seconds"))
            }
        }
    }
}
