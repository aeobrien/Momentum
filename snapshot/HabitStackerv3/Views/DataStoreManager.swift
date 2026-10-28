import Foundation
import CoreData
import Combine

final class DataStoreManager: ObservableObject {
    static let shared = DataStoreManager()
    private static var hasInitialized = false
    
    @Published private(set) var isTestingModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTestingModeEnabled, forKey: testingModeKey)
            if oldValue != isTestingModeEnabled {
                print("[DataStoreManager] isTestingModeEnabled: \(isTestingModeEnabled)")
                switchDataStore()
            }
        }
    }
    
    @Published private(set) var storeChangeID = UUID()
    
    private let testingModeKey = "isTestingModeEnabled"
    
    private init() {
        // Ensure singleton is only initialized once
        if DataStoreManager.hasInitialized {
            fatalError("[DataStoreManager] ERROR: Attempting to create multiple instances of DataStoreManager singleton!")
        }
        DataStoreManager.hasInitialized = true
        
        let savedTestingMode = UserDefaults.standard.bool(forKey: testingModeKey)
        self.isTestingModeEnabled = savedTestingMode
        
        // Use the shared CoreDataStack instance instead of creating new ones
        print("[DataStoreManager] Initialized with \(savedTestingMode ? "testing" : "personal") mode")
    }
    
    func toggleTestingMode() {
        isTestingModeEnabled.toggle()
    }
    
    private func switchDataStore() {
        // Save any pending changes in the current context
        CoreDataStack.shared.saveContext()
        
        // Reset the current context to clear any cached objects
        CoreDataStack.shared.viewContext.reset()
        
        // Generate new ID to force view recreation
        storeChangeID = UUID()
        
        print("[CoreData] Switched to \(isTestingModeEnabled ? "testing" : "personal") mode")
        print("[Injection] Updated environment with persistent store")
        
        // Post notification for any listeners
        NotificationCenter.default.post(name: .dataStoreDidChange, object: nil)
        
        // Important: The app needs to be restarted for the store change to take effect
        print("[CoreData] NOTE: App restart required for store change to take full effect")
    }
    
    var viewContext: NSManagedObjectContext {
        CoreDataStack.shared.viewContext
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        CoreDataStack.shared.newBackgroundContext()
    }
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        CoreDataStack.shared.performBackgroundTask(block)
    }
    
    func saveContext() {
        CoreDataStack.shared.saveContext()
    }
}

extension Notification.Name {
    static let dataStoreDidChange = Notification.Name("dataStoreDidChange")
}