import SwiftUI
import CoreData

struct RoutineTemplateOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var selectedTemplate: DefaultRoutineTemplate?
    @State private var selectedTasks: [RoutineBuilder.SelectableTaskTemplate] = []
    @State private var customTasks: [RoutineBuilder.CustomTaskEntry] = []
    @State private var routineName: String = ""
    @State private var currentStep = 1
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private let routineBuilder = RoutineBuilder()
    
    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case 1:
                    TemplateSelectionView(
                        selectedTemplate: $selectedTemplate,
                        onNext: moveToTaskSelection
                    )
                case 2:
                    TaskSelectionView(
                        selectedTasks: $selectedTasks,
                        routineName: $routineName,
                        templateName: selectedTemplate?.name ?? "",
                        onNext: moveToCustomTasks,
                        onBack: { currentStep = 1 }
                    )
                case 3:
                    CustomTaskEntryView(
                        customTasks: $customTasks,
                        selectedTemplateTasks: selectedTasks.filter { $0.isSelected }.map { $0.template },
                        onNext: moveToConfirmation,
                        onBack: { currentStep = 2 }
                    )
                case 4:
                    ReorderableConfirmationView(
                        routineName: routineName,
                        selectedTasks: selectedTasks.filter { $0.isSelected }.map { $0.template },
                        customTasks: customTasks.filter { !$0.name.isEmpty },
                        onConfirm: { orderedTasks in
                            createRoutineWithOrder(orderedTasks)
                        },
                        onBack: { currentStep = 3 }
                    )
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Create Routine")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func moveToTaskSelection() {
        guard let template = selectedTemplate else { return }
        
        selectedTasks = template.tasks.map { task in
            RoutineBuilder.SelectableTaskTemplate(template: task, isSelected: true)
        }
        routineName = template.name
        currentStep = 2
    }
    
    private func moveToCustomTasks() {
        currentStep = 3
    }
    
    private func moveToConfirmation() {
        currentStep = 4
    }
    
    private func createRoutine() {
        let selectedTemplates = selectedTasks.filter { $0.isSelected }.map { $0.template }
        let validCustomTasks = customTasks.filter { !$0.name.isEmpty }
        
        do {
            let routine = try routineBuilder.createRoutine(
                name: routineName,
                selectedTemplates: selectedTemplates,
                customEntries: validCustomTasks
            )
            
            // Save context
            try viewContext.save()
            
            dismiss()
        } catch {
            alertMessage = "Failed to create routine: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func createRoutineWithOrder(_ orderedTasks: [ReorderableTaskItem]) {
        // Separate template and custom tasks while preserving order
        var selectedTemplates: [DefaultTaskTemplate] = []
        var validCustomTasks: [RoutineBuilder.CustomTaskEntry] = []
        
        for task in orderedTasks {
            if let template = task.originalTemplate {
                selectedTemplates.append(template)
            } else if let custom = task.originalCustomEntry {
                validCustomTasks.append(custom)
            }
        }
        
        do {
            let routine = try routineBuilder.createRoutineWithOrder(
                name: routineName,
                orderedTasks: orderedTasks
            )
            
            // Save context
            try viewContext.save()
            
            dismiss()
        } catch {
            alertMessage = "Failed to create routine: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

// MARK: - Step 1: Template Selection

struct TemplateSelectionView: View {
    @Binding var selectedTemplate: DefaultRoutineTemplate?
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose a Template")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)
            
            Text("Select a routine template to start with")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(DefaultTemplates.templates) { template in
                        TemplateCard(
                            template: template,
                            isSelected: selectedTemplate?.id == template.id,
                            onSelect: {
                                selectedTemplate = template
                            }
                        )
                    }
                }
                .padding()
            }
            
            Button(action: onNext) {
                Text("Next")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedTemplate != nil ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(selectedTemplate == nil)
            .padding()
        }
    }
}

struct TemplateCard: View {
    let template: DefaultRoutineTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(template.tasks.count) tasks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Step 2: Task Selection

struct TaskSelectionView: View {
    @Binding var selectedTasks: [RoutineBuilder.SelectableTaskTemplate]
    @Binding var routineName: String
    let templateName: String
    let onNext: () -> Void
    let onBack: () -> Void
    
    var selectedCount: Int {
        selectedTasks.filter { $0.isSelected }.count
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Customize Tasks")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select which tasks to include")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Routine Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Enter routine name", text: $routineName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($selectedTasks.indices, id: \.self) { index in
                        TemplateTaskSelectionRow(
                            task: selectedTasks[index].template,
                            isSelected: $selectedTasks[index].isSelected
                        )
                    }
                }
                .padding()
            }
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                Button(action: onNext) {
                    Text("Next (\(selectedCount) tasks)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedCount > 0 ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(selectedCount == 0 || routineName.isEmpty)
            }
            .padding()
        }
    }
}

struct TemplateTaskSelectionRow: View {
    let task: DefaultTaskTemplate
    @Binding var isSelected: Bool
    
    private func priorityColor(_ priority: DefaultTaskTemplate.TaskPriority) -> Color {
        switch priority {
        case .essential: return .red
        case .core: return .orange
        case .nonEssential: return .green
        }
    }
    
    var body: some View {
        HStack {
            Toggle(isOn: $isSelected) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(.body)
                        
                        HStack(spacing: 12) {
                            Label("\(task.suggestedDuration) min", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if task.repetitionIntervalDays > 0 {
                                Label("Every \(task.repetitionIntervalDays) days", systemImage: "repeat")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Text(task.priority.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priorityColor(task.priority).opacity(0.2))
                        .foregroundColor(priorityColor(task.priority))
                        .cornerRadius(6)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

// MARK: - Step 3: Custom Task Entry

struct CustomTaskEntryView: View {
    @Binding var customTasks: [RoutineBuilder.CustomTaskEntry]
    let selectedTemplateTasks: [DefaultTaskTemplate]
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Add Custom Tasks")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Add your own tasks to this routine")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Show selected template tasks
                    if !selectedTemplateTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tasks from template:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(selectedTemplateTasks) { task in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text(task.name)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(task.suggestedDuration) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    
                    // Custom tasks section
                    VStack(spacing: 12) {
                        ForEach(customTasks.indices, id: \.self) { index in
                            CustomTaskRow(task: $customTasks[index])
                        }
                        
                        Button(action: addNewTask) {
                            Label("Add Task", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                Button(action: onNext) {
                    Text("Next")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
        }
    }
    
    private func addNewTask() {
        customTasks.append(RoutineBuilder.CustomTaskEntry())
    }
}

struct CustomTaskRow: View {
    @Binding var task: RoutineBuilder.CustomTaskEntry
    
    var body: some View {
        VStack(spacing: 12) {
            TextField("Task name", text: $task.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Stepper("\(task.duration) min", value: $task.duration, in: 1...120, step: 5)
                }
                
                VStack(alignment: .leading) {
                    Text("Priority")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Priority", selection: $task.priority) {
                        ForEach(DefaultTaskTemplate.TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            HStack {
                Text("Repeat interval")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Stepper("\(task.repetitionIntervalDays) days", value: $task.repetitionIntervalDays, in: 0...30)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

// MARK: - Step 4: Confirmation

struct ConfirmationView: View {
    let routineName: String
    let selectedTasks: [DefaultTaskTemplate]
    let customTasks: [RoutineBuilder.CustomTaskEntry]
    let onCreate: () -> Void
    let onBack: () -> Void
    
    var totalTasks: Int {
        selectedTasks.count + customTasks.count
    }
    
    var estimatedDuration: Int {
        let templateDuration = selectedTasks.reduce(0) { $0 + $1.suggestedDuration }
        let customDuration = customTasks.reduce(0) { $0 + $1.duration }
        return templateDuration + customDuration
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Confirm Routine")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Review your new routine")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(routineName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    Label("\(totalTasks) tasks", systemImage: "checkmark.circle")
                    Label("\(estimatedDuration) min", systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !selectedTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Template Tasks")
                                .font(.headline)
                            
                            ForEach(selectedTasks) { task in
                                HStack {
                                    Text(task.name)
                                        .font(.body)
                                    Spacer()
                                    Text("\(task.suggestedDuration) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    if !customTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Custom Tasks")
                                .font(.headline)
                            
                            ForEach(customTasks) { task in
                                HStack {
                                    Text(task.name)
                                        .font(.body)
                                    Spacer()
                                    Text("\(task.duration) min")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                Button(action: onBack) {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                Button(action: onCreate) {
                    Text("Create Routine")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
        }
    }
}

#Preview {
    RoutineTemplateOnboardingView()
}