import SwiftUI

struct ContentView: View {
    @StateObject private var taskViewModel = TaskViewModel()
    @StateObject private var routineViewModel = RoutineViewModel()
    
    // State variable to track the selected tab tag
    @State private var selectedTabTag: Int = 0 // Default to Tasks tab (tag 0)
    
    #if DEBUG
    @State private var showTestView = false
    @State private var showCloudKitDebug = false
    #endif
    
    var body: some View {
        // Pass the binding to the selected tab tag
        TabView(selection: $selectedTabTag) {
            // Tasks Tab
            NavigationView {
                TaskListView(viewModel: taskViewModel)
                    .navigationTitle("Tasks")
            }
            .tabItem {
                Label("Tasks", systemImage: "list.bullet")
            }
            .tag(0) // Assign tag 0
            
            // Routines Tab
            NavigationView {
                RoutineListView(viewModel: routineViewModel)
                    .navigationTitle("Routines")
            }
            .tabItem {
                Label("Routines", systemImage: "star.fill")
            }
            .tag(1) // Assign tag 1
            
            // Schedule Tab
            NavigationView {
                RoutineSelectionView(viewModel: routineViewModel)
                    .navigationTitle("Schedule")
            }
            .tabItem {
                Label("Schedule", systemImage: "clock.fill")
            }
            .tag(2) // Assign tag 2
            
            // Todo Tab
            NavigationView {
                ToDoView()
            }
            .tabItem {
                Label("To Do", systemImage: "checkmark.circle")
            }
            .tag(3) // Assign tag 3
            
            // Settings Tab
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(4) // Assign tag 4
        }
        #if DEBUG
        .sheet(isPresented: $showCloudKitDebug) {
            CloudKitDebugView()
        }
        #endif
        .cloudKitSyncStatus() // Add CloudKit sync status indicator
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
