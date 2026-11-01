import Foundation

/// Version represents the versioning schema for the Task Storage System
///
/// Conforms to Codable and Comparable to support encoding/decoding and version comparison.
///
/// - Important: Implements Comparable to facilitate version comparisons based on major, minor, and patch numbers.
struct Version: Codable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    
    /// Compares two Version instances
    static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}


