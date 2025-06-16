import SwiftUI

struct ContentView: View {
    @StateObject private var taskViewModel = TaskViewModel()
    @StateObject private var routineViewModel = RoutineViewModel()
    
    // State variable to track the selected tab tag
    @State private var selectedTabTag: Int = 0 // Default to Tasks tab (tag 0)
    
    // Constant for the crash action tag
    private let crashActionTabTag = 99
    
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
            
            #if DEBUG
            // Crash Report Tab (Action Trigger)
            Text("Crash Report Action Trigger") // Placeholder view
                .tabItem {
                    Label("Crash", systemImage: "exclamationmark.triangle.fill")
                }
                .tag(crashActionTabTag) // Assign the special tag
            #endif
        }
        .onChange(of: selectedTabTag) { newTag in
            #if DEBUG
            // Check if the Crash Action tab was selected
            if newTag == crashActionTabTag {
                print("[ContentView.onChange] Crash Action Tab (\(newTag)) selected!")
                // Trigger the crash report generation
                InternalLogManager.shared.generateAndAppendCrashReport()
                print("[ContentView.onChange] Called generateAndAppendCrashReport.")
                
                // Switch back to the default tab *after a short delay*
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Check if we are still on the crash tab tag before switching back
                    // Avoids accidentally switching if the user quickly tapped another tab.
                    if selectedTabTag == crashActionTabTag {
                        selectedTabTag = 0 // Switch back to Tasks tab
                        print("[ContentView.onChange] Switched selectedTabTag back to 0 after delay.")
                    } else {
                        print("[ContentView.onChange] User navigated away before delayed switch. No change made.")
                    }
                }
            }
            #endif
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
