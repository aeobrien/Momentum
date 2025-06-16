import SwiftUI
import CoreData
import UniformTypeIdentifiers // Import needed for UTType

// Helper Struct for Share Sheet
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct RoutineListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var viewModel: RoutineViewModel
    @FetchRequest private var cdRoutines: FetchedResults<CDRoutine>
    @State private var showCreateRoutine = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    // State for Export/Import
    @State private var showShareSheet = false
    @State private var showFileImporter = false
    @State private var routineFileURLToShare: URL? = nil // URL for temp file
    
    private let logger = RoutineLogger(category: "RoutineListView")
    
    init(viewModel: RoutineViewModel) {
        self.viewModel = viewModel
        
        // Initialize FetchRequest with default sorting by name
        let request: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDRoutine.name, ascending: true)]
        
        _cdRoutines = FetchRequest(
            fetchRequest: request,
            animation: .default
        )
    }
    
    var body: some View {
        List {
                ForEach(cdRoutines, id: \.uuid) { cdRoutine in
                    NavigationLink(
                        destination: RoutineDetailView(cdRoutine: cdRoutine, viewModel: viewModel)
                    ) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cdRoutine.name ?? "")
                                    .font(.headline)
                                Text("\(cdRoutine.taskRelations?.count ?? 0) tasks")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(cdRoutine.lastUsed ?? Date(), style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle("Routines")
            .toolbar { // Replaced navigationBarItems with .toolbar
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { // Import from File Button
                        showFileImporter = true
                    } label: {
                        Label("Import from File", systemImage: "square.and.arrow.down")
                    }
                    
                    Button { // Paste from Clipboard Button
                        pasteRoutinesFromClipboard()
                    } label: {
                        Label("Paste JSON", systemImage: "doc.on.clipboard")
                    }
                    
                    Button { // Export Button
                        exportRoutines()
                    } label: {
                        Label("Export Routines", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { // Add Button
                        showCreateRoutine = true
                    } label: {
                        Label("Add Routine", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateRoutine) {
                CreateRoutineView(viewModel: viewModel)
            }
            .sheet(isPresented: $showShareSheet) { // Share Sheet for Export
                if let url = routineFileURLToShare { // Use the file URL
                    ActivityViewControllerWrapper(activityItems: [url]) // Pass URL
                        .onDisappear { // Clean up temp file when sheet is dismissed
                            cleanupTempFile()
                        }
                } else {
                    // Optional: Show an alert if data is nil
                    Text("Error preparing data for sharing.")
                }
            }
            .fileImporter( // File Importer for Import
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.json], // Allow only JSON files
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        logger.error("No URL received from file importer.")
                        errorMessage = "Could not get the selected file."
                        showErrorAlert = true
                        return
                    }
                    importRoutines(from: url)
                case .failure(let error):
                    logger.error("File import failed", error: error)
                    errorMessage = "Failed to import file: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
            .onReceive(viewModel.$errorMessage) { error in
                if let error = error {
                    self.errorMessage = error
                    self.showErrorAlert = true
                    logger.error("Error received from ViewModel: \(error)")
                }
            }
    }
    
    // --- Paste from Clipboard Function --- 
    private func pasteRoutinesFromClipboard() {
        logger.info("Attempting to import routines from clipboard...")
        guard let jsonString = UIPasteboard.general.string, !jsonString.isEmpty else {
            logger.warning("Clipboard does not contain a non-empty string.")
            errorMessage = "Clipboard does not contain text to import."
            showErrorAlert = true
            return
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert clipboard string to UTF-8 data.")
            errorMessage = "Could not read text from clipboard as valid data."
            showErrorAlert = true
            return
        }
        
        // Use the refactored import logic
        processImportedRoutines(from: data)
    }
    
    // --- Export Function --- 
    private func exportRoutines() {
        logger.info("Attempting to export routines...")
        let routinesToExport = cdRoutines.map { $0.toDomainModel() }
        logger.debug("Processing \(routinesToExport.count) routines for export.")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(routinesToExport)
            logger.info("Successfully encoded \(routinesToExport.count) routines.")
            
            // --- Save data to a temporary file ---
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "Momentum_Routines_\(Date().timeIntervalSince1970).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try data.write(to: fileURL, options: .atomic)
            logger.info("Successfully saved routine data to temporary file: \(fileURL.path)")
            
            // --- Prepare for sharing ---
            self.routineFileURLToShare = fileURL // Store the URL
            self.showShareSheet = true // Show the sheet
            
        } catch {
            logger.error("Failed during export process. Error: \(String(describing: error))")
            logger.error("Localized Error Description: \(error.localizedDescription)")
            
            errorMessage = "Could not prepare routines for export: \(error.localizedDescription)"
            showErrorAlert = true
            self.routineFileURLToShare = nil // Ensure URL is nil on error
        }
    }
    
    // --- Helper to cleanup temporary file ---
    private func cleanupTempFile() {
        if let url = routineFileURLToShare {
            do {
                try FileManager.default.removeItem(at: url)
                logger.info("Successfully removed temporary export file: \(url.path)")
            } catch {
                logger.warning("Could not remove temporary export file: \(url.path). Error: \(error.localizedDescription)")
            }
            // Clear the state variable regardless
            self.routineFileURLToShare = nil
        }
    }
    
    // --- Import Function (File Picker Entry Point) --- 
    private func importRoutines(from url: URL) {
        logger.info("Attempting to import routines from URL: \(url.lastPathComponent)")
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to start accessing security scoped resource for import URL.")
            errorMessage = "Could not access the selected file."
            showErrorAlert = true
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            // Call the refactored processing function
            processImportedRoutines(from: data)
        } catch {
            logger.error("Failed to read data from file URL", error: error)
            errorMessage = "Failed to read data from the selected file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    // --- Core Import Logic (Used by File Picker & Paste) ---
    private func processImportedRoutines(from data: Data) {
        logger.info("Processing imported routine data (\(data.count) bytes)...")
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601 // Match encoding strategy
            
            let importedRoutines = try decoder.decode([Routine].self, from: data)
            logger.info("Successfully decoded \(importedRoutines.count) routines.")
            
            var createdCount = 0
            var updatedCount = 0
            
            // Fetch existing routines in one go for efficiency
            let existingRequest: NSFetchRequest<CDRoutine> = CDRoutine.fetchRequest()
            // Filter by UUIDs present in the imported data
            let importedUUIDs = importedRoutines.map { UUID(uuidString: $0.id) }.compactMap { $0 }
            guard !importedUUIDs.isEmpty else {
                logger.info("Imported data contains no valid routine UUIDs. Nothing to import.")
                // Maybe show a less alarming message?
                errorMessage = "The imported data contained no valid routines."
                showErrorAlert = true
                return
            }
            existingRequest.predicate = NSPredicate(format: "uuid IN %@", importedUUIDs)
            
            let existingRoutinesDict = try viewContext.fetch(existingRequest).reduce(into: [UUID: CDRoutine]()) {
                if let id = $1.uuid { $0[id] = $1 }
            }
            
            // Process each imported routine
            for importedRoutine in importedRoutines {
                guard let routineUUID = UUID(uuidString: importedRoutine.id) else {
                    logger.warning("Skipping import of routine with invalid UUID: \(importedRoutine.id)")
                    continue // Skip this one
                }
                
                if let existingRoutine = existingRoutinesDict[routineUUID] {
                    // Update existing routine
                    logger.debug("Updating existing routine: \(importedRoutine.name) (UUID: \(routineUUID))")
                    existingRoutine.updateCDRoutine(from: importedRoutine, context: viewContext)
                    updatedCount += 1
                } else {
                    // Create new routine
                    logger.debug("Creating new routine: \(importedRoutine.name) (UUID: \(routineUUID))")
                    let newRoutine = CDRoutine(context: viewContext)
                    newRoutine.updateCDRoutine(from: importedRoutine, context: viewContext)
                    createdCount += 1
                }
            }
            
            // Save changes if any routines were processed
            if createdCount > 0 || updatedCount > 0 {
                try viewContext.save()
                logger.info("Successfully imported routines. Created: \(createdCount), Updated: \(updatedCount)")
                // Provide user feedback on success
                errorMessage = "Import successful: \(createdCount) created, \(updatedCount) updated."
                showErrorAlert = true // Use the error alert mechanism for success message
            } else {
                logger.info("No new routines created or updated.")
                errorMessage = "No changes were made. Routines might already exist or data was invalid."
                showErrorAlert = true
            }
            
        } catch let decodingError as DecodingError {
            logger.error("Failed to decode routines JSON: \(String(describing: decodingError))")
            errorMessage = "Failed to decode routines. Ensure the clipboard contains valid Routine JSON. Error: \(decodingError.localizedDescription)"
            showErrorAlert = true
        } catch {
            logger.error("Failed during routine import processing", error: error)
            errorMessage = "Failed to process imported routines: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let cdRoutine = cdRoutines[index]
            logger.info("Deleting routine: \(cdRoutine.name ?? "")")
            
            // Remove all task relations first
            if let relations = cdRoutine.taskRelations as? Set<CDRoutineTask> {
                for relation in relations {
                    viewContext.delete(relation)
                }
            }
            
            viewContext.delete(cdRoutine)
        }
        
        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to delete routine", error: error)
            errorMessage = "Failed to delete routine: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}
