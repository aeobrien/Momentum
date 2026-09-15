import SwiftUI
import OSLog // Import the OSLog framework
import CoreData // Import CoreData

@main
struct HabitStackerApp: App {
    /// Persistence controller for Core Data integration.
    let persistenceController = PersistenceController.shared
    /// View model for managing the routine running state. Needs the context.
    @StateObject var routineRunnerViewModel: RoutineRunnerViewModel
    /// Environment scene phase to detect background/foreground transitions.
    @Environment(\.scenePhase) var scenePhase
    /// Logger for app lifecycle events.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HabitStackerApp")

    // Initialize ViewModel with the context
    init() {
        let context = persistenceController.container.viewContext
        _routineRunnerViewModel = StateObject(wrappedValue: RoutineRunnerViewModel(context: context))
        logger.info("HabitStackerApp initialized, RoutineRunnerViewModel created with context.")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(routineRunnerViewModel) // Inject the view model
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    /// Handles changes in the app's scene phase (active, inactive, background).
    /// This is crucial for pausing/resuming the timer correctly when the app is backgrounded.
    /// - Parameter newPhase: The new scene phase the app has entered.
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            logger.info("App became active.")
            // App is in the foreground and interactive.
            routineRunnerViewModel.appDidEnterForeground()
        case .inactive:
            logger.info("App became inactive.")
            // App is in the foreground but not receiving events (e.g., multitasking switcher).
            // It's often a good place to pause ongoing tasks that shouldn't run when inactive.
            // However, for a timer, we might want it to keep running briefly until it hits background.
            // Depending on exact needs, pausing here might be considered.
             routineRunnerViewModel.appWillResignActive() // Potentially pause here if needed
        case .background:
            logger.info("App entered background.")
            // App is in the background. Pause the timer and record the time.
            routineRunnerViewModel.appDidEnterBackground()
        @unknown default:
            logger.warning("Unknown scene phase encountered.")
            // Handle future cases if Apple adds more.
            // Maybe pause timer as a safe default?
            routineRunnerViewModel.pauseTimer() // Or a specific handler for unknown
        }
    }
} 