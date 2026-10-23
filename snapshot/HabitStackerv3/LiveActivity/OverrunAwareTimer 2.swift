import SwiftUI

public struct OverrunAwareTimer: View {
    public let end: Date
    
    public init(end: Date) {
        self.end = end
    }

    public var body: some View {
        if end > .now {
            // System-driven countdown to 00:00
            Text(timerInterval: .now...end, countsDown: true)
                .monospacedDigit()
        } else {
            // After end, show how long you've overrun (counting UP)
            HStack(spacing: 0) {
                Text("-")
                Text(end, style: .timer) // counts up since `end`
            }
            .monospacedDigit()
            .foregroundColor(.red)
        }
    }
}
