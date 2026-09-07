import SwiftUI

struct InfoModalView: View {
    let title: String
    let description: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            // Description
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // Dismiss button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            }) {
                Text("Got it")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .frame(maxWidth: 320)
    }
}

// Helper view modifier for consistent info overlay behavior
struct InfoOverlay: ViewModifier {
    @Binding var showInfo: Bool
    let title: String
    let description: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: showInfo ? 3 : 0)
                .animation(.easeInOut(duration: 0.2), value: showInfo)
            
            if showInfo {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInfo = false
                        }
                    }
                    .transition(.opacity)
                
                InfoModalView(
                    title: title,
                    description: description,
                    isPresented: $showInfo
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showInfo)
    }
}

extension View {
    func infoOverlay(showInfo: Binding<Bool>, title: String, description: String) -> some View {
        modifier(InfoOverlay(showInfo: showInfo, title: title, description: description))
    }
}

// Info button component for navigation bars
struct InfoButton: View {
    @Binding var showInfo: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showInfo.toggle()
            }
        }) {
            Image(systemName: "info.circle")
                .font(.system(size: 20))
                .foregroundColor(.blue)
        }
    }
}