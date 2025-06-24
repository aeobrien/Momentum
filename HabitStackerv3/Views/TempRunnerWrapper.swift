import SwiftUI

// Wrapper to maintain runner state across view updates
class TempRunnerWrapper: ObservableObject {
    @Published var runner: TempRoutineRunner?
}