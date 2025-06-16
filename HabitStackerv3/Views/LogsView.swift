// LogsView.swift
import SwiftUI

struct LogsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var logManager = InternalLogManager.shared
    @State private var selectedSession: LogSession?
    @State private var searchText = ""
    @State private var selectedLevel: LogLevel?
    @State private var showingCopiedAlert = false
    @State private var copiedAlertType: CopiedAlertType = .sessionLogs // To differentiate alerts
    @State private var sortOrder: SortOrder = .descending
    
    // Enum to manage different copy alerts
    enum CopiedAlertType {
        case sessionLogs
        case crashReports
    }
    
    private var sortedSessions: [LogSession] {
        let sessions = logManager.getAllSessions()
        return sessions.sorted {
            sortOrder == .descending ? $0.startTime > $1.startTime : $0.startTime < $1.startTime
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // List of log sessions
                List {
                    ForEach(sortedSessions) { session in
                        LogSessionRow(
                            session: session,
                            isCurrentSession: session.id == logManager.currentSession.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copySessionToClipboard(session)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
                // Crash Report Section
                VStack(spacing: 10) {
                    Text("Crash Reports")
                        .font(.headline)
                    
                    HStack(spacing: 20) {
                        Button {
                            copyCrashReportsToClipboard()
                        } label: {
                            Label("Copy Crash Reports", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(role: .destructive) { // Use destructive role for clarity
                            logManager.clearCrashReportsLog()
                        } label: {
                            Label("Clear Crash Reports", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red) // Make clear button red
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground)) // Match list style background
                
            }
            .navigationTitle("Log Sessions")
            .navigationBarItems(
                leading: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: HStack {
                    // Sort button for sessions
                    Button(action: {
                        sortOrder = sortOrder == .ascending ? .descending : .ascending
                    }) {
                        Label("Sort", systemImage: sortOrder == .descending ? "arrow.up" : "arrow.down")
                    }
                    
                    // Clear all sessions button
                    Button(action: {
                        logManager.clearAllLogs()
                    }) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .tint(.red) // Make clear all button red
                }
            )
        }
        .alert(isPresented: $showingCopiedAlert) {
            // Use the state variable to show the correct message
            let title: Text
            let message: Text
            switch copiedAlertType {
            case .sessionLogs:
                title = Text("Copied")
                message = Text("Session logs have been copied to clipboard.")
            case .crashReports:
                title = Text("Copied")
                message = Text("Crash reports log has been copied to clipboard.")
            }
            return Alert(
                title: title,
                message: message,
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func copySessionToClipboard(_ session: LogSession) {
        UIPasteboard.general.string = logManager.getFormattedSessionLogs(session)
        copiedAlertType = .sessionLogs // Set alert type
        showingCopiedAlert = true
    }
    
    // Function to copy crash reports
    private func copyCrashReportsToClipboard() {
        let reportLog = logManager.getCrashReportsLog()
        if !reportLog.isEmpty {
            UIPasteboard.general.string = reportLog
            copiedAlertType = .crashReports // Set alert type
            showingCopiedAlert = true
        } else {
            // Optionally show a different alert if the log is empty
            print("Crash report log is empty, nothing to copy.")
        }
    }
}

struct LogSessionRow: View {
    let session: LogSession
    let isCurrentSession: Bool
    
    private var errorCount: Int {
        session.records.filter { $0.level == .error || $0.level == .fatal }.count
    }
    
    private var warningCount: Int {
        session.records.filter { $0.level == .warning }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formattedDate(session.startTime))
                    .font(.headline)
                
                if isCurrentSession {
                    Text("(Current)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(formatDuration(session.duration))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Label("\(session.records.count) logs", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if errorCount > 0 {
                    Label("\(errorCount)", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if warningCount > 0 {
                    Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}
