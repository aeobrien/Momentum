import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var scheduleBufferMinutes: Int {
        didSet {
            UserDefaults.standard.set(scheduleBufferMinutes, forKey: Keys.scheduleBufferMinutes)
        }
    }
    
    @Published var backgroundNotificationIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(backgroundNotificationIntervalSeconds, forKey: Keys.backgroundNotificationIntervalSeconds)
        }
    }
    
    @Published var noTimersMode: Bool {
        didSet {
            UserDefaults.standard.set(noTimersMode, forKey: Keys.noTimersMode)
        }
    }
    
    private struct Keys {
        static let scheduleBufferMinutes = "scheduleBufferMinutes"
        static let backgroundNotificationIntervalSeconds = "backgroundNotificationIntervalSeconds"
        static let noTimersMode = "noTimersMode"
    }
    
    private init() {
        // Load saved buffer or default to 15 minutes
        self.scheduleBufferMinutes = UserDefaults.standard.object(forKey: Keys.scheduleBufferMinutes) as? Int ?? 15
        // Load saved notification interval or default to 60 seconds
        self.backgroundNotificationIntervalSeconds = UserDefaults.standard.object(forKey: Keys.backgroundNotificationIntervalSeconds) as? Int ?? 60
        // Load saved No Timers mode or default to false (timers enabled)
        self.noTimersMode = UserDefaults.standard.object(forKey: Keys.noTimersMode) as? Bool ?? false
    }
    
    func resetToDefaults() {
        scheduleBufferMinutes = 15
        backgroundNotificationIntervalSeconds = 60
        noTimersMode = false
    }
}