//
//  SplashScreenView.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 26/10/2024.
//

import Foundation
import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false

    var body: some View {
        if isActive {
            ContentView()
        } else {
            VStack(spacing: 20) {
                Text("Momentum")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("by Aidan O'Brien")
                    .font(.system(size: 24, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}
