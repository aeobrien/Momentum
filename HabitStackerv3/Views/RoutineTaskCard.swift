import SwiftUI

struct RoutineTaskCard: View {
    let task: CustomTask
    
    private func essentialityColor(_ value: Int) -> Color {
        switch value {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .gray
        }
    }
    
    private var durationText: String {
        if task.minDuration == task.maxDuration {
            return "\(task.minDuration)m"
        } else {
            return "\(task.minDuration)-\(task.maxDuration)m"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(task.taskName)
                .font(.system(size: 16, weight: .medium))
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(durationText)
                    .foregroundColor(.gray)
                    .font(.subheadline)
                
                Text(task.essentiality == 3 ? "Essential" :
                     task.essentiality == 2 ? "Core" : "Optional")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(essentialityColor(task.essentiality ?? 1).opacity(0.2))
                    .foregroundColor(essentialityColor(task.essentiality ?? 1))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}
