import SwiftUI
import UserNotifications

struct SplashScreenView: View {
    @State private var isActive = false

    var body: some View {
        NavigationStack {
            VStack {
                if isActive {
                    TimePickerView() // Automatically transition to TimePickerView after 3 seconds
                } else {
                    VStack {
                        Text("HabitStacker")
                            .font(.system(size: 40, weight: .bold, design: .serif)) // Elegant typeface
                            .foregroundColor(.primary)
                            .padding()

                        Text("by Aidan O'Brien")
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity) // Optionally add a transition effect
                }
            }
            .onAppear {
                requestNotificationPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        isActive = true
                    }
                }
            }
        }
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView()
    }
}

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        if granted {
            print("Notification permission granted.")
        } else if let error = error {
            print("Notification permission denied: \(error)")
        }
    }
}
