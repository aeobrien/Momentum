// HabitStackerv3/Views/SyncSettingsView.swift
// LifePlanner sync settings view for Momentum.

import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var syncService: SyncService

    @State private var serverURL: String = ""
    @State private var autoSync: Bool = false
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var testResultSuccess = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("http://192.168.1.100:8000", text: $serverURL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .onChange(of: serverURL) { newValue in
                        syncService.serverURL = newValue
                    }

                Toggle("Auto-sync after routine completion", isOn: $autoSync)
                    .onChange(of: autoSync) { newValue in
                        syncService.autoSyncEnabled = newValue
                    }
            }

            Section("Actions") {
                Button {
                    Task {
                        let success = await syncService.testConnection()
                        testResultSuccess = success
                        testResultMessage = success
                            ? "Connected successfully"
                            : (syncService.lastError ?? "Connection failed")
                        showingTestResult = true
                    }
                } label: {
                    Label("Test Connection", systemImage: "network")
                }

                Button {
                    Task { await syncService.sync() }
                } label: {
                    if syncService.isSyncing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                        }
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncService.isSyncing || serverURL.isEmpty)
            }

            Section("Status") {
                if let lastSync = syncService.lastSyncDate {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text("Last sync: \(lastSync, formatter: Self.dateFormatter)")
                            .font(.caption)
                    }
                }

                if let result = syncService.lastSyncResult {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(result)
                            .font(.caption)
                    }
                }

                if let error = syncService.lastError {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .navigationTitle("LifePlanner Sync")
        .onAppear {
            serverURL = syncService.serverURL
            autoSync = syncService.autoSyncEnabled
        }
        .alert(
            testResultSuccess ? "Connection OK" : "Connection Failed",
            isPresented: $showingTestResult
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(testResultMessage)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
