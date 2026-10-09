import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.2), value: progress)
    }
}

struct ConcentricProgressView: View {
    let outerProgress: Double // Routine progress
    let innerProgress: Double // Task progress
    let size: CGFloat
    var innerProgressColor: Color = .blue // Default to blue, can be overridden
    
    var body: some View {
        ZStack {
            // Outer ring background
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 13)
                .frame(width: size, height: size)
            
            // Outer ring progress (routine)
            CircularProgressView(
                progress: outerProgress,
                lineWidth: 13,
                color: .green
            )
            .frame(width: size, height: size)
            
            // Inner ring background
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 13)
                .frame(width: size - 30, height: size - 30)
            
            // Inner ring progress (task)
            CircularProgressView(
                progress: innerProgress,
                lineWidth: 13,
                color: innerProgressColor
            )
            .frame(width: size - 30, height: size - 30)
        }
    }
}