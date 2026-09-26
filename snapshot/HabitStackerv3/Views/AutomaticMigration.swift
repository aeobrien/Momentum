import Foundation
import CoreData

class AutomaticMigration {
    static let shared = AutomaticMigration()
    private init() {}
    
    private let migrationKey = "MomentumToMomentum3MigrationCompleted"
    private let migrationDateKey = "MomentumToMomentum3MigrationDate"
    
    /// Performs automatic migration if needed
    /// This should be called before Core Data stack initialization
    func performMigrationIfNeeded() {
        print("\n=== Automatic Migration Check ===")
        
        // Check if migration has already been performed
        if UserDefaults.standard.bool(forKey: migrationKey) {
            if let migrationDate = UserDefaults.standard.object(forKey: migrationDateKey) as? Date {
                print("Migration already performed on: \(migrationDate)")
            } else {
                print("Migration already performed")
            }
            return
        }
        
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        let oldStoreURL = storeDirectory.appendingPathComponent("Momentum.sqlite")
        let newStoreURL = storeDirectory.appendingPathComponent("Momentum 3.sqlite")
        
        // Check if old store exists
        guard FileManager.default.fileExists(atPath: oldStoreURL.path) else {
            print("No old store found - no migration needed")
            // Mark as migrated so we don't check again
            markMigrationComplete()
            return
        }
        
        // Check if new store already exists and has data
        if FileManager.default.fileExists(atPath: newStoreURL.path) {
            do {
                let newStoreAttributes = try FileManager.default.attributesOfItem(atPath: newStoreURL.path)
                let newStoreSize = newStoreAttributes[.size] as? Int ?? 0
                
                // If new store exists and is larger than empty DB (>100KB), don't migrate
                if newStoreSize > 100_000 {
                    print("New store already exists with data (size: \(newStoreSize) bytes)")
                    print("Skipping migration to avoid data loss")
                    markMigrationComplete()
                    return
                }
                
                print("New store exists but appears empty (size: \(newStoreSize) bytes)")
            } catch {
                print("Error checking new store: \(error)")
            }
        }
        
        // Perform the migration
        performMigration(from: oldStoreURL, to: newStoreURL)
    }
    
    private func performMigration(from oldStoreURL: URL, to newStoreURL: URL) {
        print("\n=== Performing Automatic Migration ===")
        
        do {
            // Get size of old store for verification
            let oldStoreAttributes = try FileManager.default.attributesOfItem(atPath: oldStoreURL.path)
            let oldStoreSize = oldStoreAttributes[.size] as? Int ?? 0
            print("Old store size: \(oldStoreSize) bytes")
            
            // Backup new store if it exists
            if FileManager.default.fileExists(atPath: newStoreURL.path) {
                let backupURL = newStoreURL.deletingPathExtension().appendingPathExtension("backup.sqlite")
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.copyItem(at: newStoreURL, to: backupURL)
                print("Backed up existing new store")
            }
            
            // Remove new store and associated files
            let newStoreFiles = [
                newStoreURL,
                newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm"),
                newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            ]
            
            for file in newStoreFiles {
                try? FileManager.default.removeItem(at: file)
            }
            
            // Copy old store to new location
            try FileManager.default.copyItem(at: oldStoreURL, to: newStoreURL)
            print("Successfully copied old store to new location")
            
            // Copy WAL and SHM files if they exist
            let oldShmURL = oldStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let oldWalURL = oldStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            let newShmURL = newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let newWalURL = newStoreURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            
            if FileManager.default.fileExists(atPath: oldShmURL.path) {
                try? FileManager.default.copyItem(at: oldShmURL, to: newShmURL)
                print("Copied SHM file")
            }
            
            if FileManager.default.fileExists(atPath: oldWalURL.path) {
                try? FileManager.default.copyItem(at: oldWalURL, to: newWalURL)
                print("Copied WAL file")
            }
            
            // Verify the copy
            let newStoreAttributes = try FileManager.default.attributesOfItem(atPath: newStoreURL.path)
            let newStoreSize = newStoreAttributes[.size] as? Int ?? 0
            
            if newStoreSize == oldStoreSize {
                print("Migration successful! Store sizes match.")
                markMigrationComplete()
                
                // Optional: Archive old store instead of deleting
                archiveOldStore(at: oldStoreURL)
            } else {
                print("Warning: Store sizes don't match. Old: \(oldStoreSize), New: \(newStoreSize)")
            }
            
        } catch {
            print("Migration failed: \(error)")
            // If migration fails, the app will continue with existing data
        }
    }
    
    private func markMigrationComplete() {
        UserDefaults.standard.set(true, forKey: migrationKey)
        UserDefaults.standard.set(Date(), forKey: migrationDateKey)
        print("Migration marked as complete")
    }
    
    private func archiveOldStore(at url: URL) {
        // Instead of deleting, rename the old store with a timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let archiveURL = url.deletingPathExtension().appendingPathExtension("archived-\(timestamp).sqlite")
        
        do {
            try FileManager.default.moveItem(at: url, to: archiveURL)
            print("Archived old store to: \(archiveURL.lastPathComponent)")
            
            // Also archive SHM and WAL files
            let shmURL = url.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let walURL = url.deletingPathExtension().appendingPathExtension("sqlite-wal")
            let archiveShmURL = archiveURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
            let archiveWalURL = archiveURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
            
            try? FileManager.default.moveItem(at: shmURL, to: archiveShmURL)
            try? FileManager.default.moveItem(at: walURL, to: archiveWalURL)
            
        } catch {
            print("Failed to archive old store: \(error)")
        }
    }
    
    /// Reset migration for testing purposes
    static func resetMigration() {
        UserDefaults.standard.removeObject(forKey: AutomaticMigration.shared.migrationKey)
        UserDefaults.standard.removeObject(forKey: AutomaticMigration.shared.migrationDateKey)
    }
}