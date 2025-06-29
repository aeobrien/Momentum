import Foundation
import CloudKit
import SwiftUI

/// CloudKitSyncManager provides a centralized way to monitor and manage CloudKit sync status
class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()
    
    @Published var syncStatus: SyncStatus = .unknown
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var isSyncing: Bool = false
    
    enum SyncStatus: Equatable {
        case unknown
        case available
        case unavailable
        case error(String)
        
        var description: String {
            switch self {
            case .unknown:
                return "Checking iCloud status..."
            case .available:
                return "iCloud sync active"
            case .unavailable:
                return "iCloud not available"
            case .error(let message):
                return "Sync error: \(message)"
            }
        }
        
        var symbolName: String {
            switch self {
            case .unknown:
                return "icloud"
            case .available:
                return "icloud.fill"
            case .unavailable:
                return "icloud.slash"
            case .error:
                return "exclamationmark.icloud"
            }
        }
        
        var color: Color {
            switch self {
            case .unknown:
                return .gray
            case .available:
                return .green
            case .unavailable:
                return .orange
            case .error:
                return .red
            }
        }
    }
    
    private init() {
        checkCloudKitStatus()
        setupAccountChangeNotification()
    }
    
    /// Check current CloudKit availability and account status
    func checkCloudKitStatus() {
        let container = CKContainer(identifier: "iCloud.AOTondra.Momentum")
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.syncStatus = .error(error.localizedDescription)
                    self.syncError = error.localizedDescription
                    return
                }
                
                switch status {
                case .available:
                    self.syncStatus = .available
                    self.syncError = nil
                case .noAccount:
                    self.syncStatus = .unavailable
                    self.syncError = "Please sign in to iCloud in Settings"
                case .restricted:
                    self.syncStatus = .unavailable
                    self.syncError = "iCloud access is restricted"
                case .couldNotDetermine:
                    self.syncStatus = .unknown
                    self.syncError = "Could not determine iCloud status"
                case .temporarilyUnavailable:
                    self.syncStatus = .unavailable
                    self.syncError = "iCloud is temporarily unavailable"
                @unknown default:
                    self.syncStatus = .unknown
                    self.syncError = "Unknown iCloud status"
                }
            }
        }
    }
    
    /// Setup notification for iCloud account changes
    private func setupAccountChangeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accountChanged),
            name: .CKAccountChanged,
            object: nil
        )
    }
    
    @objc private func accountChanged() {
        checkCloudKitStatus()
        
        // Force sync when account status changes
        if syncStatus == .available {
            CloudKitPreferences.shared.forceSync()
        }
    }
    
    /// Update last sync date
    func updateLastSyncDate() {
        DispatchQueue.main.async {
            self.lastSyncDate = Date()
            UserDefaults.standard.set(self.lastSyncDate, forKey: "lastCloudKitSyncDate")
        }
    }
    
    /// Start syncing indicator
    func startSyncing() {
        DispatchQueue.main.async {
            self.isSyncing = true
        }
    }
    
    /// Stop syncing indicator
    func stopSyncing() {
        DispatchQueue.main.async {
            self.isSyncing = false
            self.updateLastSyncDate()
        }
    }
    
    /// Handle CloudKit errors with user-friendly messages
    func handleError(_ error: Error) {
        guard let ckError = error as? CKError else {
            DispatchQueue.main.async {
                self.syncError = error.localizedDescription
                self.syncStatus = .error(error.localizedDescription)
            }
            return
        }
        
        DispatchQueue.main.async {
            switch ckError.code {
            case .networkUnavailable:
                self.syncError = "No network connection"
                self.syncStatus = .unavailable
            case .networkFailure:
                self.syncError = "Network error - will retry"
                self.syncStatus = .unavailable
            case .quotaExceeded:
                self.syncError = "iCloud storage full"
                self.syncStatus = .error("Storage quota exceeded")
            case .notAuthenticated:
                self.syncError = "Not signed in to iCloud"
                self.syncStatus = .unavailable
            case .permissionFailure:
                self.syncError = "iCloud permission denied"
                self.syncStatus = .error("Permission denied")
            case .accountTemporarilyUnavailable:
                self.syncError = "iCloud temporarily unavailable"
                self.syncStatus = .unavailable
            default:
                self.syncError = ckError.localizedDescription
                self.syncStatus = .error(ckError.localizedDescription)
            }
        }
    }
}

/// View modifier to show sync status in the UI
struct CloudKitSyncStatusModifier: ViewModifier {
    @ObservedObject var syncManager = CloudKitSyncManager.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if syncManager.syncStatus != .available {
                    HStack(spacing: 4) {
                        if syncManager.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: syncManager.syncStatus.symbolName)
                                .foregroundColor(syncManager.syncStatus.color)
                        }
                    }
                    .padding(8)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(8)
                    .shadow(radius: 2)
                    .padding()
                }
            }
    }
}

extension View {
    /// Add CloudKit sync status indicator to any view
    func cloudKitSyncStatus() -> some View {
        self.modifier(CloudKitSyncStatusModifier())
    }
}