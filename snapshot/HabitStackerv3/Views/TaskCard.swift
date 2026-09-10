import SwiftUI

struct TaskCard: View {
    @ObservedObject var cdTask: CDTask
    let isSelected: Bool
    var onRemove: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil

    private func essentialityColor(_ value: Int16) -> Color {
        switch value {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .gray
        }
    }

    private var durationText: String {
        if cdTask.minDuration == cdTask.maxDuration {
            return "\(cdTask.minDuration)m"
        } else {
            return "\(cdTask.minDuration)-\(cdTask.maxDuration)m"
        }
    }
    
    var body: some View {
        HStack {
            if isSelected {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.gray)
                    .padding(.trailing, 4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cdTask.taskName ?? "")
                    .font(.headline)

                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.gray)
                    Text(durationText)
                        .foregroundColor(.gray)
                }
                .font(.subheadline)
            }
            
            Spacer()
            
            Text(cdTask.essentiality == 3 ? "Essential" :
                 cdTask.essentiality == 2 ? "Core" : "Optional")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(essentialityColor(cdTask.essentiality).opacity(0.2))
                .foregroundColor(essentialityColor(cdTask.essentiality))
                .cornerRadius(8)
            
            if isSelected {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .imageScale(.large)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}
