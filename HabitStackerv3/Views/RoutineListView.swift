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
    @State private var showTemplateOnboarding = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var searchText: String = ""
    @State private var sortMode: RoutineSortMode = .nameAsc
    @State private var infoMode = false
    @State private var showDeleteConfirmation = false
    @State private var routineToDelete: CDRoutine? = nil
    
    // State for Export/Import
    @State private var showShareSheet = false
    @State private var showFileImporter = false
    @State private var routineFileURLToShare: URL? = nil // URL for temp file
    
    private let logger = RoutineLogger(category: "RoutineListView")
    
    private var filteredAndSortedRoutines: [CDRoutine] {
        let filtered = Array(cdRoutines.filter { routine in
            searchText.isEmpty || (routine.name ?? "").localizedCaseInsensitiveContains(searchText)
        })
        
        return filtered.sorted { (routine1: CDRoutine, routine2: CDRoutine) -> Bool in
            switch sortMode {
            case .nameAsc:
                return (routine1.name ?? "") < (routine2.name ?? "")
            case .nameDesc:
                return (routine1.name ?? "") > (routine2.name ?? "")
            case .mostTasks:
                return (routine1.taskRelations?.count ?? 0) > (routine2.taskRelations?.count ?? 0)
            case .fewestTasks:
                return (routine1.taskRelations?.count ?? 0) < (routine2.taskRelations?.count ?? 0)
            case .longestFirst:
                return totalDuration(for: routine1) > totalDuration(for: routine2)
            case .shortestFirst:
                return totalDuration(for: routine1) < totalDuration(for: routine2)
            case .newestFirst:
                return (routine1.lastUsed ?? Date.distantPast) > (routine2.lastUsed ?? Date.distantPast)
            case .oldestFirst:
                return (routine1.lastUsed ?? Date.distantPast) < (routine2.lastUsed ?? Date.distantPast)
            }
        }
    }
    
    private func totalDuration(for routine: CDRoutine) -> Int {
        guard let relations = routine.taskRelations as? Set<CDRoutineTask> else {
            return 0
        }
        return relations.compactMap { $0.task }.reduce(0) { total, task in
            total + Int(task.minDuration)
        }
    }
    
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
        ZStack {
            VStack(spacing: 0) {
            // Search and Sort Section
            VStack(spacing: 12) {
                HStack {
                    RoutineSearchBar(text: $searchText)
                    
                    Menu {
                        ForEach(RoutineSortMode.allCases, id: \.self) { mode in
                            Button(action: {
                                sortMode = mode
                                logger.debug("Sort mode changed to: \(mode.rawValue)")
                            }) {
                                HStack {
                                    Text(mode.rawValue)
                                    if sortMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .foregroundColor(.blue)
                            .imageScale(.large)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.bottom, 12)
            .background(Color(.systemBackground))
            
            Divider()
            
            // Routines List
            if filteredAndSortedRoutines.isEmpty {
                VStack(spacing: 16) {
                    Text("No Routines Yet!")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    if searchText.isEmpty {
                        Button(action: {
                            showTemplateOnboarding = true
                        }) {
                            Text("Tap here to create your first routine from a template.")
                                .foregroundColor(.blue)
                                .underline()
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)
                    } else {
                        Text("Try adjusting your search")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredAndSortedRoutines, id: \.objectID) { cdRoutine in
                        NavigationLink(
                            destination: RoutineDetailView(cdRoutine: cdRoutine, viewModel: viewModel)
                        ) {
                            RoutineCard(cdRoutine: cdRoutine)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                routineToDelete = cdRoutine
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        }
        .infoOverlay(
            showInfo: $infoMode,
            title: "Routines",
            description: "Manage your routines here. Each routine shows its task count, last run date, and duration. Tap a routine to view or edit it."
        )
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                InfoButton(showInfo: $infoMode)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        showCreateRoutine = true
                    }) {
                        Label("Create Custom Routine", systemImage: "square.and.pencil")
                    }
                    
                    Button(action: {
                        showTemplateOnboarding = true
                    }) {
                        Label("Create from Template", systemImage: "doc.text")
                    }
                } label: {
                    Label("Add Routine", systemImage: "plus")
                }
            }
        }
        .fullScreenCover(isPresented: $showCreateRoutine) {
            CreateRoutineView(viewModel: viewModel)
        }
        .sheet(isPresented: $showTemplateOnboarding) {
            RoutineTemplateOnboardingView()
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
        .alert("Delete Routine?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                routineToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let routine = routineToDelete {
                    deleteRoutine(routine)
                }
                routineToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(routineToDelete?.name ?? "this routine")\"? This action cannot be undone.")
        }
        .onReceive(viewModel.$errorMessage) { error in
            if let error = error {
                self.errorMessage = error
                self.showErrorAlert = true
                logger.error("Error received from ViewModel: \(error)")
            }
        }
    }
    
    private func deleteRoutine(_ cdRoutine: CDRoutine) {
        logger.info("Deleting routine: \(cdRoutine.name ?? "")")
        
        // Remove all task relations first
        if let relations = cdRoutine.taskRelations as? Set<CDRoutineTask> {
            for relation in relations {
                viewContext.delete(relation)
            }
        }
        
        viewContext.delete(cdRoutine)
        
        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to delete routine", error: error)
            errorMessage = "Failed to delete routine: \(error.localizedDescription)"
            showErrorAlert = true
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
}
