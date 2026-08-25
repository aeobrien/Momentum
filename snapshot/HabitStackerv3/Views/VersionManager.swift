import Foundation

/// VersionManager handles version comparison and migration processes
final class VersionManager {
    
    /// Compares two versions and returns the higher one
    /// - Parameters:
    ///   - local: Local version
    ///   - other: Other version
    /// - Returns: The higher version
    func compareVersions(_ local: Version, _ other: Version) -> Version {
        return max(local, other)
    }
    
    /// Applies necessary migrations based on version differences
    /// - Parameters:
    ///   - currentVersion: Current version
    ///   - newVersion: New version to migrate to
    /// - Throws: TaskStorageError.versionMismatch if migration fails
    func migrate(from currentVersion: Version, to newVersion: Version) throws {
        // Implement migration logic based on version differences
        // Example:
        if currentVersion.major < newVersion.major {
            // Handle major version migrations
        }
        if currentVersion.minor < newVersion.minor {
            // Handle minor version migrations
        }
        if currentVersion.patch < newVersion.patch {
            // Handle patch version migrations
        }
        // After migration, ensure data integrity
    }
}
