import SwiftUI
import CoreData

struct RoutineCard: View {
    @ObservedObject var cdRoutine: CDRoutine
    
    private var taskCountText: String {
        let count = cdRoutine.taskRelations?.count ?? 0
        return count == 1 ? "1 task" : "\(count) tasks"
    }
    
    private var essentialDuration: Int {
        guard let relations = cdRoutine.taskRelations as? Set<CDRoutineTask> else {
            return 0
        }
        
        return relations.compactMap { $0.task }.filter { $0.essentiality == 3 }.reduce(0) { total, task in
            total + Int(task.minDuration)
        }
    }
    
    private var coreAndEssentialDuration: Int {
        guard let relations = cdRoutine.taskRelations as? Set<CDRoutineTask> else {
            return 0
        }
        
        return relations.compactMap { $0.task }.filter { $0.essentiality >= 2 }.reduce(0) { total, task in
            total + Int(task.minDuration)
        }
    }
    
    private var totalDuration: Int {
        guard let relations = cdRoutine.taskRelations as? Set<CDRoutineTask> else {
            return 0
        }
        
        return relations.compactMap { $0.task }.reduce(0) { total, task in
            total + Int(task.minDuration)
        }
    }
    
    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
    
    private var lastUsedText: String {
        guard let lastUsed = cdRoutine.lastUsed else {
            return "Never used"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(cdRoutine.name ?? "Unnamed Routine")
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.gray)
                    Text(taskCountText)
                        .foregroundColor(.gray)
                }
                .font(.subheadline)
                
                Text("Last used: \(lastUsedText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Duration pills stacked vertically
            VStack(alignment: .trailing, spacing: 4) {
                // Essential duration (red) - top
                if essentialDuration > 0 {
                    Text(formatDuration(essentialDuration))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                
                // Core + Essential duration (orange) - middle
                if coreAndEssentialDuration > 0 {
                    Text(formatDuration(coreAndEssentialDuration))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
                
                // Total duration (green) - bottom
                Text(formatDuration(totalDuration))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}