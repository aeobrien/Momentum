import SwiftUI
import CoreData

struct RoutineTestView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var testResults: String = ""
    @State private var isRunningTest = false
    @State private var selectedTestCount = 1
    @State private var showBatchOptions = false
    
    private let testHarness = RoutineTestHarness()
    private let logger = AppLogger.create(subsystem: "com.app.RoutineTestView", category: "Testing")

    
    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Test Controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test Controls")
                            .font(.headline)
                        
                        Button("Run Single Random Test") {
                            runSingleRandomTest()
                        }
                        .disabled(isRunningTest)
                        
                        Button("Run Test Batch") {
                            showBatchOptions = true
                        }
                        .disabled(isRunningTest)
                        
                        if isRunningTest {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    
                    // Results Display
                    if !testResults.isEmpty {
                        Text("Test Results")
                            .font(.headline)
                        
                        Text(testResults)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Routine Tests")
            .sheet(isPresented: $showBatchOptions) {
                BatchTestOptionsView(selectedCount: $selectedTestCount) {
                    showBatchOptions = false
                    runTestBatch(count: selectedTestCount)
                }
            }
        }
    
    private func runSingleRandomTest() {
            isRunningTest = true
            logger.info("Starting Random Test")
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try testHarness.runRandomTest()
                    DispatchQueue.main.async {
                        testResults = """
                            RANDOM TEST RESULTS:
                            -------------------
                            \(result.analysis)
                            """
                        logger.info("Random test completed successfully")
                    }
                } catch {
                    DispatchQueue.main.async {
                        testResults = """
                            TEST FAILED:
                            -----------
                            Error: \(error.localizedDescription)
                            """
                        logger.error("Random test failed", error: error)
                    }
                }
                
                DispatchQueue.main.async {
                    isRunningTest = false
                }
            }
        }
    
    private func runTestBatch(count: Int) {
            isRunningTest = true
            logger.info("Starting Batch Test with count: \(count)")
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let results = try testHarness.runRandomTestBatch(count: count)
                    DispatchQueue.main.async {
                        testResults = results
                        logger.info("Batch test completed successfully")
                    }
                } catch {
                    DispatchQueue.main.async {
                        testResults = """
                            BATCH TEST FAILED:
                            ----------------
                            Error: \(error.localizedDescription)
                            """
                        logger.error("Batch test failed", error: error)
                    }
                }
                
                DispatchQueue.main.async {
                    isRunningTest = false
                }
            }
        }
}

struct BatchTestOptionsView: View {
    @Binding var selectedCount: Int
    let onRun: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Batch Size")) {
                    Picker("Number of Tests", selection: $selectedCount) {
                        ForEach([1, 5, 10, 20, 50, 100], id: \.self) { count in
                            Text("\(count) tests").tag(count)
                        }
                    }
                }
                
                Section {
                    Button("Run Batch Test") {
                        presentationMode.wrappedValue.dismiss()
                        onRun()
                    }
                }
            }
            .navigationTitle("Batch Test Options")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
