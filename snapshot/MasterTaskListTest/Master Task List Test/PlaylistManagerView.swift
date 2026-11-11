import SwiftUI

struct PlaylistManagerView: View {
    @Binding var refreshTrigger: Bool
    @State private var playlists: [String] = []
    @State private var showingPlaylistCreator = false
    @State private var showingDeleteAlert = false
    @State private var playlistToDelete: String?
    @State private var editingPlaylist: String?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(playlists, id: \.self) { playlist in
                    HStack {
                        Text(playlist)
                        Spacer()
                        Button("Edit") {
                            editingPlaylist = playlist
                        }
                    }
                }
                .onDelete(perform: deletePlaylist)
            }
            .navigationBarTitle("Manage Playlists")
            .navigationBarItems(trailing: Button("Add Playlist") {
                showingPlaylistCreator = true
            })
        }
        .onAppear(perform: loadPlaylists)
        .sheet(isPresented: $showingPlaylistCreator) {
            PlaylistCreatorView(refreshTrigger: $refreshTrigger, onDismiss: loadPlaylists)
        }
        .sheet(item: $editingPlaylist) { playlist in
            PlaylistCreatorView(refreshTrigger: $refreshTrigger, editingPlaylist: playlist, onDismiss: loadPlaylists)
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Playlist"),
                message: Text("Are you sure you want to delete this playlist?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let playlist = playlistToDelete {
                        deletePlaylistFile(playlist)
                        loadPlaylists()
                        refreshTrigger.toggle()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func loadPlaylists() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bundleURL = Bundle.main.resourceURL!
        
        do {
            let documentFiles = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let bundleFiles = try fileManager.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
            
            let allFiles = documentFiles + bundleFiles
            
            playlists = allFiles.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix("Routine.json") }
                .map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Routine", with: "") }
            
            print("Found playlists: \(playlists)")
        } catch {
            print("Error while loading playlists: \(error)")
        }
    }
    
    private func deletePlaylist(at offsets: IndexSet) {
        if let index = offsets.first {
            playlistToDelete = playlists[index]
            showingDeleteAlert = true
        }
    }
    
    private func deletePlaylistFile(_ playlist: String) {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("\(playlist)Routine.json")
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted playlist: \(playlist)")
        } catch {
            print("Error deleting playlist: \(error)")
        }
    }
}

extension String: Identifiable {
    public var id: String { self }
}
