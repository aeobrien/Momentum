import SwiftUI
import CryptoKit

enum RepetitionUnit: String, CaseIterable, Identifiable {
    case hours = "Hours"
    case days = "Days"
    case weeks = "Weeks"

    var id: String { self.rawValue }
    
    var secondsMultiplier: Int {
        switch self {
        case .hours:
            return 3600
        case .days:
            return 86400
        case .weeks:
            return 604800
        }
    }
}

enum Essentiality: Int, CaseIterable, Identifiable {
    case essential = 3
    case core = 2
    case nonEssential = 1
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        switch self {
        case .essential:
            return "Essential"
        case .core:
            return "Core"
        case .nonEssential:
            return "Non-essential"
        }
    }
}

struct EditTaskView: View {
    @Binding var task: CustomTask
    var onSave: () -> Void
    var isNewTask: Bool = false
    
    @State private var repetitionValue: Int = 1
    @State private var repetitionUnit: RepetitionUnit = .hours
    @State private var isCustomRepetition: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Task Details").font(.headline)) {
                TextField("Task Name", text: $task.taskName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.bottom, 10)
                
                Picker("Essentiality", selection: Binding<Int>(
                    get: { task.essentiality ?? Essentiality.core.rawValue },
                    set: { task.essentiality = $0 }
                )) {
                    ForEach(Essentiality.allCases) { essentiality in
                        Text(essentiality.displayName).tag(essentiality.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.bottom, 10)
            }
            
            Section(header: Text("Duration").font(.headline)) {
                HStack {
                    Stepper("", value: Binding(
                        get: { task.minDuration / 60 },
                        set: { newValue in
                            if task.minDuration == task.maxDuration {
                                task.maxDuration = newValue * 60
                            }
                            task.minDuration = newValue * 60
                        }
                    ), in: 1...Int.max, step: 1)
                    .labelsHidden()
                    
                    TextField("Min Duration", value: Binding(
                        get: { task.minDuration / 60 },
                        set: { newValue in
                            if task.minDuration == task.maxDuration {
                                task.maxDuration = newValue * 60
                            }
                            task.minDuration = newValue * 60
                        }
                    ), formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    
                    Text("mins")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
                
                HStack {
                    Stepper("", value: Binding(
                        get: { task.maxDuration / 60 },
                        set: { newValue in
                            if newValue <= task.minDuration / 60 {
                                task.minDuration = newValue * 60
                            }
                            task.maxDuration = newValue * 60
                        }
                    ), in: 1...Int.max, step: 1)
                    .labelsHidden()
                    
                    TextField("Max Duration", value: Binding(
                        get: { task.maxDuration / 60 },
                        set: { newValue in
                            if task.maxDuration == task.minDuration {
                                task.minDuration = newValue * 60
                            }
                            task.maxDuration = newValue * 60
                        }
                    ), formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    
                    Text("mins")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            }
            
            Section(header: Text("Repetition Interval").font(.headline)) {
                if task.repetitionInterval == 0 && !isCustomRepetition {
                    Text("This task repeats daily.")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        isCustomRepetition = true
                        repetitionValue = 1
                        repetitionUnit = .hours
                    }) {
                        Text("Change Repetition Interval")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Stepper("", value: $repetitionValue, in: 1...Int.max, step: 1)
                                .labelsHidden()
                            
                            TextField("Interval", value: $repetitionValue, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        HStack {
                            Picker("Unit", selection: $repetitionUnit) {
                                ForEach(RepetitionUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        Button(action: {
                            task.repetitionInterval = 0
                            isCustomRepetition = false
                        }) {
                            Text("Set to Daily")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            
            Button(action: {
                let repetitionIntervalInSeconds = repetitionValue * repetitionUnit.secondsMultiplier
                task.repetitionInterval = isCustomRepetition ? repetitionIntervalInSeconds : 0
                
                // Generate UUID for new tasks
                if isNewTask {
                    task.UUID = generateUUID(from: task.taskName)
                }
                
                onSave()
            }) {
                Text(isNewTask ? "Add Task" : "Save Changes")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
            .padding(.top, 20)
        }
        .onAppear {
            if task.minDuration > task.maxDuration {
                task.maxDuration = task.minDuration
            }
            
            // Ensure repetition interval uses existing value
            if let interval = task.repetitionInterval, interval > 0 {
                isCustomRepetition = true
                if interval % 604800 == 0 {
                    repetitionUnit = .weeks
                    repetitionValue = interval / 604800
                } else if interval % 86400 == 0 {
                    repetitionUnit = .days
                    repetitionValue = interval / 86400
                } else {
                    repetitionUnit = .hours
                    repetitionValue = interval / 3600
                }
            } else {
                repetitionUnit = .days
                repetitionValue = 1
            }
        }
    }
    
    func formattedDuration(min: Int, max: Int) -> String {
        if min == max {
            return "\(min / 60) min"
        } else {
            return "\(min / 60)-\(max / 60) min"
        }
    }
    
    
    // UUID Generation Function
    func generateUUID(from input: String) -> String {
        let hash = Insecure.MD5.hash(data: input.data(using: .utf8) ?? Data())
        return hash.map { String(format: "%02hhx", $0) }.joined().prefix(32)
            .enumerated()
            .map { idx, char in
                [8, 12, 16, 20].contains(idx) ? "-" + String(char) : String(char)
            }
            .joined()
    }
}
