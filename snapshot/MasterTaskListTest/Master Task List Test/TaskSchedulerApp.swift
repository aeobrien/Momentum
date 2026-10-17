import SwiftUI
import UIKit
import UserNotifications
import AVFoundation

@main
struct TaskSchedulerApp: App {
    // Integrate AppDelegate with SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
        }
    }
}


class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        // Configure audio session to allow mixing with other audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session configured to allow mixing with other audio.")
        } catch {
            print("Failed to set audio session category: \(error)")
        }
        
        return true
    }


    func applicationDidEnterBackground(_ application: UIApplication) {
        print("App did enter background")
        backgroundTask = application.beginBackgroundTask {
            application.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = UIBackgroundTaskIdentifier.invalid
        }
        // Notify the active view to save its state
        NotificationCenter.default.post(name: Notification.Name("AppDidEnterBackground"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            application.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = UIBackgroundTaskIdentifier.invalid
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("App will enter foreground")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // Notify the active view to restore its state
        NotificationCenter.default.post(name: Notification.Name("AppWillEnterForeground"), object: nil)
    }

    // UNUserNotificationCenterDelegate method
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Notification received while app is in foreground")
        completionHandler([.alert, .sound])
    }
}
