import SwiftUI
import CoreData

struct RunFromSelectionView: View {
    let routine: CDRoutine
    let scheduledTasks: [ScheduledTask]
    @Binding var selectedStartIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    private let logger = AppLogger.create(subsystem: "com.app.RunFromSelectionView", category: "UI")
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Select where to start the routine from:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                
                List {
                    ForEach(Array(scheduledTasks.enumerated()), id: \.offset) { index, scheduledTask in
                        Button(action: {
                            selectedStartIndex = index
                            dismiss()
                        }) {
                            HStack {
                                Text("\(index + 1).")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(scheduledTask.task.taskName ?? "Unnamed Task")
                                        .foregroundColor(.primary)
                                    
                                    Text("\(Int(scheduledTask.allocatedDuration / 60)) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if index == 0 {
                                    Text("(Start)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Run From")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            logger.info("Showing \(scheduledTasks.count) scheduled tasks for 'run from' selection")
        }
    }
}