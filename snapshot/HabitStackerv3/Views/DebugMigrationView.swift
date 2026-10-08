import SwiftUI
import CoreData

struct DebugMigrationView: View {
    @State private var debugOutput = ""
    @State private var showingFilePicker = false
    @State private var showMainApp = false
    
    var body: some View {
        if showMainApp {
            SplashScreenView()
        } else {
        VStack {
            Text("Core Data Migration Debug")
                .font(.title)
                .padding()
            
            ScrollView {
                Text(debugOutput)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .padding()
            
            VStack(spacing: 10) {
                HStack {
                    Button("Check Stores") {
                        checkStores()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Force Migration") {
                        forceMigration()
                    }
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Import SQLite") {
                        showingFilePicker = true
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                HStack {
                    Button("Simple Copy") {
                        simpleCopy()
                    }
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Reset Flags") {
                        resetFlags()
                    }
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding()
            
            Button("Continue to App") {
                showMainApp = true
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.purple)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.horizontal)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                if let file = files.first {
                    importSQLiteFile(from: file)
                }
            case .failure(let error):
                debugOutput += "\n\nError selecting file: \(error)"
            }
        }
        }
    }
    
    private func checkStores() {
        debugOutput = ""
        
        // Check current store
        let currentStore = NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("Momentum 3.sqlite")
        
        debugOutput += "Current store (Momentum 3.sqlite):\n"
        if FileManager.default.fileExists(atPath: currentStore.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: currentStore.path)
                let size = attributes[FileAttributeKey.size] as? Int ?? 0
                debugOutput += "  Exists - Size: \(size) bytes\n"
            } catch {
                debugOutput += "  Error getting attributes: \(error)\n"
            }
        } else {
            debugOutput += "  Does not exist\n"
        }
        
        // List all SQLite files
        debugOutput += "\nAll SQLite files in store directory:\n"
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
            let sqliteFiles = files.filter { $0.pathExtension == "sqlite" }
            
            for file in sqliteFiles {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                let size = attributes[FileAttributeKey.size] as? Int ?? 0
                debugOutput += "  - \(file.lastPathComponent) (\(size) bytes)\n"
            }
            
            if sqliteFiles.isEmpty {
                debugOutput += "  No SQLite files found\n"
            }
        } catch {
            debugOutput += "  Error listing directory: \(error)\n"
        }
    }
    
    private func forceMigration() {
        debugOutput += "\n\n=== Forcing Migration ===\n"
        
        // Reset migration flag
        UserDefaults.standard.set(false, forKey: "HasMigratedFromMomentumToMomentum3")
        
        // Run migration
        CoreDataMigration.shared.migrateFromOldStore()
        
        debugOutput += "Migration attempted. Check console for details.\n"
    }
    
    private func importSQLiteFile(from url: URL) {
        debugOutput += "\n\n=== Importing SQLite File ===\n"
        debugOutput += "Source: \(url.lastPathComponent)\n"
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            debugOutput += "Failed to access file\n"
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        CoreDataMigration.shared.importSQLiteFile(from: url)
        
        debugOutput += "Import attempted. Check console for details.\n"
        debugOutput += "You may need to restart the app for changes to take effect.\n"
    }
    
    private func simpleCopy() {
        debugOutput += "\n\n=== Simple Copy Migration ===\n"
        SimpleMigration.copyOldDataToNewStore()
        debugOutput += "Simple copy attempted. Check console for details.\n"
        debugOutput += "IMPORTANT: Restart the app after this operation!\n"
    }
    
    private func resetFlags() {
        debugOutput += "\n\n=== Resetting Migration Flags ===\n"
        SimpleMigration.resetMigration()
        debugOutput += "Migration flags reset.\n"
    }
}