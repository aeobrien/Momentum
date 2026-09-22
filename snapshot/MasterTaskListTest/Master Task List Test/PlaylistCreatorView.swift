import SwiftUI

struct PlaylistCreatorView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var refreshTrigger: Bool
    var editingPlaylist: String?
    var onDismiss: (() -> Void)?
    
    @State private var allTasks: [CustomTask] = []
    @State private var selectedTasks: [CustomTask] = []
    @State private var playlistName: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("Playlist Name", text: $playlistName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                List {
                    Section(header: Text("Selected Tasks")) {
                        ForEach(selectedTasks) { task in
                            TaskRow(task: task, isSelected: true) {
                                selectedTasks.removeAll { $0.UUID == task.UUID }
                            }
                        }
                        .onMove(perform: moveTask)
                    }
                    
                    Section(header: Text("Available Tasks")) {
                        ForEach(allTasks.filter { task in
                            !selectedTasks.contains { $0.UUID == task.UUID }
                        }) { task in
                            TaskRow(task: task, isSelected: false) {
                                selectedTasks.append(task)
                            }
                        }
                    }
                }
                .listStyle(GroupedListStyle())
                
                Button(editingPlaylist == nil ? "Save Playlist" : "Update Playlist") {
                    savePlaylist()
                }
                .padding()
                .disabled(playlistName.isEmpty || selectedTasks.isEmpty)
            }
            .navigationBarTitle(editingPlaylist == nil ? "Create Playlist" : "Edit Playlist", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Playlist Creation"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .onAppear(perform: loadData)
    }
    
    private func loadData() {
        loadTasks()
        if let editingPlaylist = editingPlaylist {
            loadExistingPlaylist(editingPlaylist)
        }
    }
    
    private func loadTasks() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("FullTaskListv2.json")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                allTasks = try JSONDecoder().decode([CustomTask].self, from: data)
                print("Successfully loaded \(allTasks.count) tasks from FullTaskListv2.json")
            } catch {
                print("Error loading tasks from documents directory: \(error)")
                loadTasksFromBundle()
            }
        } else {
            loadTasksFromBundle()
        }
        
        print("All task UUIDs: \(allTasks.map { $0.UUID })")
    }
    
    private func loadTasksFromBundle() {
        if let url = Bundle.main.url(forResource: "FullTaskListv2", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                allTasks = try JSONDecoder().decode([CustomTask].self, from: data)
                print("Successfully loaded \(allTasks.count) tasks from bundle")
            } catch {
                print("Error loading tasks from bundle: \(error)")
            }
        }
    }
    
    private func loadExistingPlaylist(_ playlist: String) {
        playlistName = playlist
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("\(playlist)Routine.json")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            loadPlaylistFromURL(fileURL)
        } else if let bundleURL = Bundle.main.url(forResource: "\(playlist)Routine", withExtension: "json") {
            loadPlaylistFromURL(bundleURL)
        } else {
            print("Error: Playlist file not found in documents directory or bundle")
        }
    }
    
    private func loadPlaylistFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decodedPlaylist = try JSONDecoder().decode(CustomPlaylist.self, from: data)
            selectedTasks = allTasks.filter { decodedPlaylist.taskUUIDs.contains($0.UUID) }
            print("Loaded playlist: \(playlistName)")
            print("Number of tasks in playlist: \(selectedTasks.count)")
            print("Task UUIDs in playlist: \(decodedPlaylist.taskUUIDs)")
        } catch {
            print("Error loading existing playlist: \(error)")
        }
    }
    
    private func moveTask(from source: IndexSet, to destination: Int) {
        selectedTasks.move(fromOffsets: source, toOffset: destination)
    }
    
    private func savePlaylist() {
        let playlist = CustomPlaylist(playlistName: playlistName,
                                      createdOn: ISO8601DateFormatter().string(from: Date()),
                                      taskUUIDs: selectedTasks.map { $0.UUID })
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(playlist)
            
            let fileName = "\(playlistName)Routine.json"
            if let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentDirectory.appendingPathComponent(fileName)
                try data.write(to: fileURL)
                print("Playlist saved successfully at: \(fileURL.path)")
                alertMessage = "Playlist saved successfully!"
                showingAlert = true
                refreshTrigger.toggle()
                onDismiss?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } catch {
            print("Error saving playlist: \(error.localizedDescription)")
            alertMessage = "Error saving playlist: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

struct TaskRow: View {
    let task: CustomTask
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(task.taskName)
            Spacer()
            Button(action: action) {
                Image(systemName: isSelected ? "minus.circle" : "plus.circle")
            }
        }
    }
}
