import SwiftUI

struct TaskProgressBarView: View {
    let value: Double // 0.0 to 1.0
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green)
                        .frame(width: geometry.size.width * value, height: 8)
                        .animation(.linear(duration: 0.3), value: value)
                }
            }
            .frame(height: 8)
            
            // Label below the bar
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 5)
    }
}