import Foundation
import CoreData

class SimpleMigration {
    static func copyOldDataToNewStore() {
        print("\n=== Simple Migration: Copying old data to new store ===")
        
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        let oldStoreURL = storeDirectory.appendingPathComponent("Momentum.sqlite")
        let newStoreURL = storeDirectory.appendingPathComponent("Momentum 3.sqlite")
        
        // Check if old store exists
        guard FileManager.default.fileExists(atPath: oldStoreURL.path) else {
            print("Old store not found at: \(oldStoreURL.path)")
            return
        }
        
        // Check if we've already migrated
        if UserDefaults.standard.bool(forKey: "SimpleMigrationCompleted") {
            print("Migration already completed")
            return
        }
        
        do {
            // First, make a backup of the current new store
            let backupURL = storeDirectory.appendingPathComponent("Momentum 3.backup.sqlite")
            if FileManager.default.fileExists(atPath: newStoreURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.copyItem(at: newStoreURL, to: backupURL)
                print("Backed up current store to: \(backupURL.lastPathComponent)")
            }
            
            // Remove the new store and its associated files
            let newStoreFiles = [
                newStoreURL,
                newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm"),
                newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            ]
            
            for file in newStoreFiles {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                    print("Removed: \(file.lastPathComponent)")
                }
            }
            
            // Copy the old store to the new location
            try FileManager.default.copyItem(at: oldStoreURL, to: newStoreURL)
            print("Copied old store to new location")
            
            // Also copy -shm and -wal files if they exist
            let oldShmURL = oldStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let oldWalURL = oldStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            let newShmURL = newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let newWalURL = newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            
            if FileManager.default.fileExists(atPath: oldShmURL.path) {
                try FileManager.default.copyItem(at: oldShmURL, to: newShmURL)
                print("Copied -shm file")
            }
            
            if FileManager.default.fileExists(atPath: oldWalURL.path) {
                try FileManager.default.copyItem(at: oldWalURL, to: newWalURL)
                print("Copied -wal file")
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: "SimpleMigrationCompleted")
            
            print("Simple migration completed successfully!")
            print("Please restart the app to see your data.")
            
        } catch {
            print("Simple migration failed: \(error)")
        }
    }
    
    static func resetMigration() {
        UserDefaults.standard.set(false, forKey: "SimpleMigrationCompleted")
        UserDefaults.standard.set(false, forKey: "HasMigratedFromMomentumToMomentum3")
        print("Migration flags reset")
    }
}