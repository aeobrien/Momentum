import SwiftUI

struct DemoContentView: View {
    @State private var timeRemaining: Int = 34
    @State private var progress: CGFloat = 0.4
    @State private var infoMode: Bool = false
    @State private var highlightedElement: String? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                HStack {
                    Button(action: {
                        if infoMode {
                            infoMode = false
                            highlightedElement = nil
                        }
                    }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(infoMode ? .blue : .blue)
                            .font(.title2)
                    }
                    Spacer()
                    Text("Morning 1/18")
                        .font(.headline)
                        .onTapGesture { if infoMode { highlightedElement = "routine" } }
                    Spacer()
                    Button(action: {
                        if infoMode {
                            infoMode = false
                            highlightedElement = nil
                        } else {
                            infoMode = true
                            highlightedElement = nil
                        }
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Text("Put on Watch")
                    .font(.system(size: 34, weight: .bold))
                    .onTapGesture { if infoMode { highlightedElement = "title" } }

                Text("Coming Up: Drink Water")
                    .font(.system(size: 20))
                    .onTapGesture { if infoMode { highlightedElement = "comingUp" } }

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 13)
                        .frame(width: 280, height: 280)
                    Circle()
                        .trim(from: 0.0, to: 0.055)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 280, height: 280)
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 13)
                        .frame(width: 250, height: 250)
                    Circle()
                        .trim(from: 0.0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 250, height: 250)
                    Text(String(format: "%02d:%02d", timeRemaining / 60, timeRemaining % 60))
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(.blue)
                        .onTapGesture { if infoMode { highlightedElement = "timer" } }
                }
                .padding(.top, 20)
                .onTapGesture { if infoMode { highlightedElement = "progress" } }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("On Schedule: 18:49 finish")
                        .foregroundColor(.green)
                        .font(.subheadline)
                        .onTapGesture { if infoMode { highlightedElement = "schedule" } }
                }

                Spacer()

                HStack(spacing: 40) {
                    Image(systemName: "forward.fill")
                        .foregroundColor(.yellow)
                        .font(.title2)
                        .onTapGesture { if infoMode { highlightedElement = "skip" } }
                    Image(systemName: "hourglass")
                        .foregroundColor(.purple)
                        .font(.title2)
                        .onTapGesture { if infoMode { highlightedElement = "delay" } }
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                        .font(.title2)
                        .onTapGesture { if infoMode { highlightedElement = "interrupt" } }
                    Image(systemName: "arrow.uturn.down")
                        .foregroundColor(.blue)
                        .font(.title2)
                        .onTapGesture { if infoMode { highlightedElement = "background" } }
                }
                .padding(.vertical, 24)

                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 48, height: 48)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                    Text("Slide to Complete")
                        .font(.body)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { if infoMode { highlightedElement = "complete" } }
                    Spacer().frame(width: 48)
                }
                .padding(.vertical, 10)
                .padding(.horizontal)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(40)
                .padding(.horizontal)

                HStack {
                    TabItem(icon: "list.bullet.rectangle", label: "Tasks")
                    TabItem(icon: "star", label: "Routines")
                    TabItem(icon: "clock", label: "Schedule", active: true)
                    TabItem(icon: "checkmark.square", label: "To Do")
                    TabItem(icon: "gear", label: "Settings")
                }
                .padding(.vertical, 16)
                .background(Color.white)
            }
            .saturation(infoMode ? 0 : 1)
            .background(Color(.systemGray6))
            .ignoresSafeArea(edges: .bottom)

            if infoMode && highlightedElement == nil {
                VStack {
                    Spacer()
                    Text("Tap anywhere for more information")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .padding(.bottom, 80)
                }
            }

            if let element = highlightedElement {
                GeometryReader { geometry in
                    ZStack {
                        Color.clear
                        Text(infoText(for: element))
                            .foregroundColor(.white)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(12)
                            .frame(maxWidth: geometry.size.width * 0.8)
                            .position(infoPosition(for: element, in: geometry.size))
                    }
                }
            }
        }
    }

    func infoText(for element: String) -> String {
        switch element {
        case "routine": return "This is the routine and current task number."
        case "title": return "Name of current task."
        case "comingUp": return "Name of next task."
        case "timer": return "Time remaining on current task."
        case "progress": return "Outer ring: overall routine. Inner ring: current task."
        case "schedule": return "How ahead or behind schedule you're currently running."
        case "skip": return "Skip current task."
        case "delay": return "Come back to this task later."
        case "interrupt": return "Temporary interruption."
        case "background": return "Send this task to the background to resume later."
        case "complete": return "Slide this to mark the current task completed."
        default: return ""
        }
    }

    func infoPosition(for element: String, in size: CGSize) -> CGPoint {
        switch element {
        case "routine": return CGPoint(x: size.width / 2, y: 70)
        case "title": return CGPoint(x: size.width / 2, y: 130)
        case "comingUp": return CGPoint(x: size.width / 2, y: 170)
        case "progress": return CGPoint(x: size.width / 2, y: 350)
        case "timer": return CGPoint(x: size.width / 2, y: 350)
        case "schedule": return CGPoint(x: size.width / 2, y: 480)
        case "skip": return CGPoint(x: size.width * 0.15, y: size.height - 240)
        case "delay": return CGPoint(x: size.width * 0.38, y: size.height - 240)
        case "interrupt": return CGPoint(x: size.width * 0.61, y: size.height - 240)
        case "background": return CGPoint(x: size.width * 0.85, y: size.height - 240)
        case "complete": return CGPoint(x: size.width / 2, y: size.height - 140)
        default: return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }
}

struct TabItem: View {
    let icon: String
    let label: String
    var active: Bool = false

    var body: some View {
        VStack {
            Image(systemName: icon)
                .foregroundColor(active ? .blue : .gray)
            Text(label)
                .font(.caption2)
                .foregroundColor(active ? .blue : .gray)
        }
        .frame(maxWidth: .infinity)
    }
}
