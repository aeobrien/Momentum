import Foundation
import CloudKit

/// CloudKitPreferences provides iCloud syncing for UserDefaults preferences
/// It automatically syncs user preferences using CloudKit when available
class CloudKitPreferences: ObservableObject {
    static let shared = CloudKitPreferences()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let recordType = "UserPreferences"
    private let recordID = CKRecord.ID(recordName: "UserPreferencesRecord")
    
    // Keys to sync (excluding debug and migration flags)
    private let syncableKeys = [
        "activeRoutineID"
    ]
    
    private init() {
        // Use the same container identifier as Core Data
        self.container = CKContainer(identifier: "iCloud.AOTondra.Momentum")
        self.privateDatabase = container.privateCloudDatabase
        
        // Setup observers for UserDefaults changes
        setupObservers()
        
        // Initial sync from CloudKit
        fetchFromCloudKit()
    }
    
    private func setupObservers() {
        // Observe changes to syncable keys
        for key in syncableKeys {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(userDefaultsDidChange(_:)),
                name: UserDefaults.didChangeNotification,
                object: nil
            )
        }
    }
    
    @objc private func userDefaultsDidChange(_ notification: Notification) {
        // Sync changes to CloudKit
        syncToCloudKit()
    }
    
    /// Sync local preferences to CloudKit
    private func syncToCloudKit() {
        // Check if iCloud is available
        guard CoreDataStack.shared.isCloudKitAvailable else {
            print("iCloud not available - skipping preference sync")
            return
        }
        
        // Create or update the preferences record
        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            let preferencesRecord: CKRecord
            if let existingRecord = record {
                preferencesRecord = existingRecord
            } else {
                preferencesRecord = CKRecord(recordType: self.recordType, recordID: self.recordID)
            }
            
            // Update record with current UserDefaults values
            for key in self.syncableKeys {
                if let value = UserDefaults.standard.object(forKey: key) {
                    preferencesRecord[key] = value as? CKRecordValue
                }
            }
            
            // Add last modified timestamp
            preferencesRecord["lastModified"] = Date() as CKRecordValue
            
            // Save to CloudKit
            self.privateDatabase.save(preferencesRecord) { savedRecord, error in
                if let error = error {
                    self.handleCloudKitError(error)
                } else {
                    print("Preferences synced to CloudKit successfully")
                }
            }
        }
    }
    
    /// Fetch preferences from CloudKit and update local UserDefaults
    func fetchFromCloudKit() {
        // Check if iCloud is available
        guard CoreDataStack.shared.isCloudKitAvailable else {
            print("iCloud not available - using local preferences only")
            return
        }
        
        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else { return }
            
            if let error = error {
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    // Record doesn't exist yet - this is normal for first run
                    print("No preferences found in CloudKit - using local values")
                    // Sync local values to CloudKit
                    self.syncToCloudKit()
                } else {
                    self.handleCloudKitError(error)
                }
                return
            }
            
            guard let record = record else { return }
            
            // Check if CloudKit record is newer than local data
            let cloudLastModified = record["lastModified"] as? Date ?? Date.distantPast
            let localLastModified = UserDefaults.standard.object(forKey: "preferencesLastModified") as? Date ?? Date.distantPast
            
            if cloudLastModified > localLastModified {
                // Update local UserDefaults with CloudKit values
                for key in self.syncableKeys {
                    if let value = record[key] {
                        UserDefaults.standard.set(value, forKey: key)
                    }
                }
                UserDefaults.standard.set(cloudLastModified, forKey: "preferencesLastModified")
                print("Preferences fetched from CloudKit successfully")
            } else {
                print("Local preferences are newer - keeping local values")
            }
        }
    }
    
    /// Handle CloudKit errors
    private func handleCloudKitError(_ error: Error) {
        guard let ckError = error as? CKError else {
            print("Non-CloudKit error in preferences sync: \(error)")
            return
        }
        
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            print("Network error - preferences will sync when connection restored")
        case .quotaExceeded:
            print("iCloud storage quota exceeded - preferences not synced")
        case .notAuthenticated:
            print("User not signed into iCloud - preferences stored locally only")
        case .permissionFailure:
            print("iCloud permission denied for preferences")
        default:
            print("CloudKit preferences error: \(ckError)")
        }
    }
    
    /// Force sync preferences (useful after significant changes)
    func forceSync() {
        fetchFromCloudKit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncToCloudKit()
        }
    }
}