import SwiftUI
import CoreData
import OSLog // Import the OSLog framework

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var routineRunnerViewModel: RoutineRunnerViewModel // Access the shared view model
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")

    // FetchRequest can be added here later when we have data
    // @FetchRequest(
    //     sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
    //     animation: .default) // Example fetch request
    // private var items: FetchedResults<Item>

    var body: some View {
        NavigationView {
            // Main content area - Initially showing the RoutineRunnerView
            RoutineRunnerView(viewModel: routineRunnerViewModel)
                .navigationTitle("Habit Stacker")
                .toolbar {
                    // Toolbar items can be added later (e.g., for selecting routines)
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton() // Example EditButton
                    }
                    #endif
                    ToolbarItem {
                        Button(action: addItem) { // Example Add button
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
                .onAppear {
                    logger.debug("ContentView appeared.")
                }
                .onDisappear {
                    logger.debug("ContentView disappeared.")
                }
            // Placeholder text if no routine is running, or for the initial view
            // Text("Select an item")
        }
    }

    // Example function to add an item (will be adapted for routines/tasks)
    private func addItem() {
        logger.info("Add item button tapped (placeholder action).")
        /*
        // Placeholder for adding Core Data items
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()

            do {
                try viewContext.save()
                logger.debug("Successfully saved new item.")
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                logger.error("Unresolved error \(nsError), \(nsError.userInfo)")
                // Consider presenting an error message to the user
                // fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        */
    }

    // Example function to delete items (will be adapted)
    private func deleteItems(offsets: IndexSet) {
        logger.info("Delete items action triggered (placeholder).")
        /*
        // Placeholder for deleting Core Data items
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
                logger.debug("Successfully deleted items.")
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                logger.error("Unresolved error \(nsError), \(nsError.userInfo)")
                // Consider presenting an error message to the user
                // fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        */
    }
}

// Persistence Controller (Standard Core Data Stack)
class PersistenceController {
    static let shared = PersistenceController()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PersistenceController")


    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // Add preview data if needed
        // for i in 0..<10 {
        //     let newItem = Item(context: viewContext)
        //     newItem.timestamp = Date()
        // }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate.
            // You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PersistenceControllerPreview").error("Unresolved error \(nsError), \(nsError.userInfo)")
            // fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        // Use the actual name of your .xcdatamodeld file
        container = NSPersistentCloudKitContainer(name: "HabitStacker")
        if inMemory {
            logger.info("Initializing Core Data stack in-memory.")
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        logger.info("Loading persistent stores...")
        container.loadPersistentStores(completionHandler: { [weak self] (storeDescription, error) in
            guard let self = self else {
                // Handle the case where self is nil (though unlikely in init)
                print("Error: PersistenceController deallocated before store loaded.") // Or use a static logger
                return
            }
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                self.logger.error("Unresolved error during persistent store load: \(error), \(error.userInfo)")
                // fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
                self.logger.info("Persistent store loaded successfully: \(storeDescription.url?.absoluteString ?? "No URL")")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}


// Preview Provider for ContentView
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            // Pass the preview context to the ViewModel initializer
            .environmentObject(RoutineRunnerViewModel(context: PersistenceController.preview.container.viewContext))
    }
} 