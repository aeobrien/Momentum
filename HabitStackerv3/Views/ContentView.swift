import SwiftUI

struct ContentView: View {
    @StateObject private var taskViewModel = TaskViewModel()
    @StateObject private var routineViewModel = RoutineViewModel()
    
    // State variable to track the selected tab tag
    @State private var selectedTabTag: Int = 0 // Default to Tasks tab (tag 0)
    @State private var showTempRoutineEntry = false
    
    // Constant for the temp action tag
    private let tempActionTabTag = 99
    
    #if DEBUG
    @State private var showTestView = false
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
                    .navigationTitle("To Do")
            }
            .tabItem {
                Label("To Do", systemImage: "checkmark.circle")
            }
            .tag(3) // Assign tag 3
            
            // Temp Routine Tab (Action Trigger)
            Text("Temp Routine Action Trigger") // Placeholder view
                .tabItem {
                    Label("Temp", systemImage: "timer")
                }
                .tag(tempActionTabTag) // Assign the special tag
        }
        .onChange(of: selectedTabTag) { newTag in
            // Check if the Temp Action tab was selected
            if newTag == tempActionTabTag {
                // Show the temp routine entry sheet
                showTempRoutineEntry = true
                
                // Switch back to the previous tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if selectedTabTag == tempActionTabTag {
                        selectedTabTag = 0 // Switch back to Tasks tab
                    }
                }
            }
        }
        .sheet(isPresented: $showTempRoutineEntry) {
            TempRoutineEntryView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
