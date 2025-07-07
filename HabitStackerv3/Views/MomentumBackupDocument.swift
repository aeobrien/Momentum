import UIKit

class MomentumBackupDocument: UIDocument {
    var backupData: BackupData?
    
    override func contents(forType typeName: String) throws -> Any {
        guard let data = backupData else {
            throw NSError(domain: "com.AOTondra.Momentum", code: 1, userInfo: [NSLocalizedDescriptionKey: "No backup data available"])
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        return try encoder.encode(data)
    }
    
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else {
            throw NSError(domain: "com.AOTondra.Momentum", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid backup data format"])
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        backupData = try decoder.decode(BackupData.self, from: data)
    }
}