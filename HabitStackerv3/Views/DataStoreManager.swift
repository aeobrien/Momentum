import Foundation
import CoreData
import Combine

final class DataStoreManager: ObservableObject {
    static let shared = DataStoreManager()
    
    @Published private(set) var isTestingModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTestingModeEnabled, forKey: testingModeKey)
            if oldValue != isTestingModeEnabled {
                print("[ToggleStore] isTestingModeEnabled: \(isTestingModeEnabled)")
                switchDataStore()
            }
        }
    }
    
    @Published private(set) var currentStack: CoreDataStack
    @Published private(set) var storeChangeID = UUID()
    
    private let personalStack: CoreDataStack
    private let testingStack: CoreDataStack
    private let testingModeKey = "isTestingModeEnabled"
    
    private init() {
        let savedTestingMode = UserDefaults.standard.bool(forKey: testingModeKey)
        self.isTestingModeEnabled = savedTestingMode
        
        self.personalStack = CoreDataStack(containerName: "Momentum 3", storeDescription: nil)
        self.testingStack = CoreDataStack(
            containerName: "Momentum 3",
            storeDescription: "MomentumTesting"
        )
        
        self.currentStack = savedTestingMode ? testingStack : personalStack
        
        print("[CoreData] Loaded \(savedTestingMode ? "testing" : "personal") dataset container")
    }
    
    func toggleTestingMode() {
        isTestingModeEnabled.toggle()
    }
    
    private func switchDataStore() {
        // Save any pending changes in the current context
        currentStack.saveContext()
        
        // Reset the current context to clear any cached objects
        currentStack.viewContext.reset()
        
        // Switch to the new stack
        currentStack = isTestingModeEnabled ? testingStack : personalStack
        
        // Generate new ID to force view recreation
        storeChangeID = UUID()
        
        print("[CoreData] Switched to \(isTestingModeEnabled ? "testing" : "personal") dataset container")
        print("[Injection] Updated environment with new persistent store")
        
        // Post notification for any listeners
        NotificationCenter.default.post(name: .dataStoreDidChange, object: nil)
    }
    
    var viewContext: NSManagedObjectContext {
        currentStack.viewContext
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        currentStack.newBackgroundContext()
    }
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        currentStack.performBackgroundTask(block)
    }
    
    func saveContext() {
        currentStack.saveContext()
    }
}

extension Notification.Name {
    static let dataStoreDidChange = Notification.Name("dataStoreDidChange")
}