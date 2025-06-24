import SwiftUI

struct TempRoutineRunnerView: View {
    @ObservedObject var runner: TempRoutineRunner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) var scenePhase
    
    @State private var detailsVisible: Bool = false
    @State private var showTaskList: Bool = false
    @State private var showingEndConfirmation = false
    @Namespace private var animation
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                if !runner.isRoutineComplete {
                    // Main Running View
                    VStack(spacing: 0) {
                        // Content area that adapts based on detailsVisible
                        ZStack {
                            VStack(spacing: 0) {
                                // Top Spacer - only in simple view
                                if !detailsVisible {
                                    Spacer()
                                }
                                
                                // Timer Display
                                Text(runner.remainingTimeString)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(runner.isOverrun ? .red : .primary)
                                    .frame(height: 40)
                                    .padding(.bottom, 10)
                                    .matchedGeometryEffect(id: "timer", in: animation)
                                    .offset(y: detailsVisible ? 0 : -50)
                                
                                // Task Name Display
                                Text(runner.currentTaskName)
                                    .font(.system(size: 46, weight: .bold, design: .rounded))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(runner.isOverrun ? .red : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(Color(.secondarySystemBackground))
                                            .shadow(radius: 3)
                                            .frame(width: geometry.size.width - 40)
                                    )
                                    .padding(.horizontal, 20)
                                    .matchedGeometryEffect(id: "taskName", in: animation)
                                    .zIndex(1)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            detailsVisible.toggle()
                                        }
                                    }
                                
                                // Progress Bar - Always visible
                                ProgressBarView(
                                    value: runner.progressFraction,
                                    label: runner.progressTaskString
                                )
                                .frame(width: geometry.size.width - 80)
                                .padding(.top, 50)
                                .offset(y: detailsVisible ? 0 : 30)
                                
                                // Detailed View Content
                                if detailsVisible {
                                    Spacer().frame(height: 20)
                                    
                                    // Status Section
                                    VStack(spacing: 12) {
                                        HStack {
                                            Image(systemName: scheduleIconName())
                                                .foregroundColor(scheduleColor())
                                            Text(runner.scheduleOffsetString)
                                                .font(.headline)
                                                .foregroundColor(scheduleColor())
                                        }
                                        
                                        Text("Estimated finish: " + estimatedFinishTime())
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(height: 90)
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .offset(y: -20)))
                                    
                                    Spacer().frame(height: 10)
                                    
                                    // Next Task Preview
                                    VStack(spacing: 8) {
                                        if let nextTaskName = runner.nextTaskName {
                                            Text("Coming up:")
                                                .font(.headline)
                                                .foregroundColor(.secondary)
                                            Text(nextTaskName)
                                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .padding(.horizontal)
                                        } else {
                                            Text("Last task in routine")
                                                .font(.headline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(height: 80)
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .offset(y: -50)))
                                    
                                    Spacer().frame(height: 15)
                                    
                                    // Action Buttons
                                    HStack(spacing: 40) {
                                        // Skip Button
                                        Button(action: runner.skipToNextTask) {
                                            VStack {
                                                Image(systemName: "forward.fill").font(.title)
                                                Text("Skip").font(.caption)
                                            }.foregroundColor(.yellow)
                                        }.disabled(runner.isRoutineComplete)
                                        
                                        // Delay Button
                                        Button(action: { runner.delayCurrentTask(by: 5) }) {
                                            VStack {
                                                Image(systemName: "hourglass").font(.title)
                                                Text("Delay").font(.caption)
                                            }.foregroundColor(.orange)
                                        }.disabled(runner.isRoutineComplete || !runner.canDelayCurrentTask)
                                        
                                        // Pause/Resume Button
                                        Button(action: runner.toggleTimer) {
                                            VStack {
                                                Image(systemName: runner.isRunning ? "pause.fill" : "play.fill").font(.title)
                                                Text(runner.isRunning ? "Pause" : "Resume").font(.caption)
                                            }.foregroundColor(.blue)
                                        }.disabled(runner.isRoutineComplete)
                                        
                                        // Tasks Button
                                        Button(action: { showTaskList.toggle() }) {
                                            VStack {
                                                Image(systemName: "list.bullet").font(.title)
                                                Text("Tasks").font(.caption)
                                            }.foregroundColor(.blue)
                                        }
                                    }
                                    .frame(height: 60)
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .offset(y: -80)))
                                    
                                    Spacer().frame(height: 10)
                                }
                                
                                // Bottom Spacer - only in simple view
                                if !detailsVisible {
                                    Spacer(minLength: 0)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                        
                        // Fixed Bottom Section (Slide to Complete)
                        VStack(spacing: 0) {
                            Divider()
                            
                            SlideToCompleteView {
                                runner.markTaskComplete()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                        }
                        .frame(height: 80)
                    }
                } else {
                    // Completion View
                    VStack {
                        Spacer()
                        Text("Routine Complete! 🎉")
                            .font(.largeTitle)
                            .padding()
                        
                        Spacer().frame(height: 40)
                        
                        Button(action: { dismiss() }) {
                            Text("Return to Schedule")
                                .font(.title2)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Temporary Routine")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !runner.isRoutineComplete {
                        Button(action: {
                            runner.endRoutine()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            .onAppear {
                if !runner.isRunning && !runner.isRoutineComplete {
                    runner.toggleTimer()
                }
            }
            .sheet(isPresented: $showTaskList) {
                NavigationView {
                    TempRoutineDetailView(runner: runner)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                // Handle scene phase changes if needed
            }
        }
    }
    
    private func scheduleIconName() -> String {
        if runner.scheduleOffsetString == "On schedule" {
            return "checkmark.circle.fill"
        } else if runner.scheduleOffsetString.contains("ahead") {
            return "arrow.up.circle.fill"
        } else if runner.scheduleOffsetString.contains("behind") {
            return "arrow.down.circle.fill"
        } else {
            return "clock.fill"
        }
    }
    
    private func scheduleColor() -> Color {
        if runner.scheduleOffsetString == "On schedule" {
            return .secondary
        } else if runner.scheduleOffsetString.contains("ahead") {
            return .green
        } else if runner.scheduleOffsetString.contains("behind") {
            return .red
        } else {
            return .primary
        }
    }
    
    private func estimatedFinishTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let totalRemaining = runner.totalRoutineDuration - runner.completedDuration
        let estimatedFinish = Date().addingTimeInterval(totalRemaining)
        return formatter.string(from: estimatedFinish)
    }
}

struct TempRoutineRunnerView_Previews: PreviewProvider {
    static var previews: some View {
        let tasks = [
            TempTask(name: "Task 1", duration: 5),
            TempTask(name: "Task 2", duration: 10),
            TempTask(name: "Task 3", duration: 15)
        ]
        let runner = TempRoutineRunner(tasks: tasks)
        
        TempRoutineRunnerView(runner: runner)
    }
}