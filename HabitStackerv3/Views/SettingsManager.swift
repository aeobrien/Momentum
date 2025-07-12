import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var scheduleBufferMinutes: Int {
        didSet {
            UserDefaults.standard.set(scheduleBufferMinutes, forKey: Keys.scheduleBufferMinutes)
        }
    }
    
    private struct Keys {
        static let scheduleBufferMinutes = "scheduleBufferMinutes"
    }
    
    private init() {
        // Load saved buffer or default to 15 minutes
        self.scheduleBufferMinutes = UserDefaults.standard.object(forKey: Keys.scheduleBufferMinutes) as? Int ?? 15
    }
    
    func resetToDefaults() {
        scheduleBufferMinutes = 15
    }
}