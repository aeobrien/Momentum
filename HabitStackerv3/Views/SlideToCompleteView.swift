//
//  SlideToCompleteView.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 28/10/2024.
//

import Foundation
import SwiftUI

struct SlideToCompleteView: View {
    let onComplete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var isCompleting: Bool = false
    @GestureState private var isDragging = false
    
    // Gradient colors
    private let gradientColors = [
        Color.blue.opacity(0.3),
        Color.blue.opacity(0.1)
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color(.systemGray6))
                
                // Gradient layer
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: offset)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                
                // "Slide to Complete" text
                Text("Slide to Complete")
                    .foregroundColor(.gray)
                    .animation(nil)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // Slider
                HStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.blue)
                        .frame(width: 60, height: 50)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: offset)
                        .gesture(
                            DragGesture()
                                .updating($isDragging) { value, state, _ in
                                    state = true
                                }
                                .onChanged { value in
                                    guard !isCompleting else { return }
                                    let newOffset = min(max(0, value.translation.width), width - 60)
                                    withAnimation(.interactiveSpring()) {
                                        offset = newOffset
                                    }
                                }
                                .onEnded { value in
                                    let threshold = width * 0.8
                                    if offset > threshold && !isCompleting {
                                        isCompleting = true
                                        
                                        // Hold at end position
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            offset = width - 60
                                        }
                                        
                                        // Delay before completing and resetting
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            onComplete()
                                            
                                            // Reset with animation
                                            withAnimation(.spring()) {
                                                offset = 0
                                                isCompleting = false
                                            }
                                        }
                                    } else {
                                        withAnimation(.spring()) {
                                            offset = 0
                                        }
                                    }
                                }
                        )
                }
                
                // Add subtle shadow to slider
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            }
            .frame(height: 50)
            .onAppear {
                width = geometry.size.width
            }
        }
        .frame(height: 50)
    }
}
