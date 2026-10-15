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
    
    private var dailyLogs: [(date: Date, logCount: Int, errorCount: Int, warningCount: Int)] {
        let sessions = logManager.getAllSessions()
        let calendar = Calendar.current
        
        // Group sessions by day
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }
        
        // Calculate totals for each day
        return grouped.map { (date, sessions) in
            let totalLogs = sessions.reduce(0) { $0 + $1.records.count }
            let totalErrors = sessions.reduce(0) { $0 + $1.records.filter { $0.level == .error || $0.level == .fatal }.count }
            let totalWarnings = sessions.reduce(0) { $0 + $1.records.filter { $0.level == .warning }.count }
            
            return (date: date, logCount: totalLogs, errorCount: totalErrors, warningCount: totalWarnings)
        }
        .sorted { sortOrder == .descending ? $0.date > $1.date : $0.date < $1.date }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // List of daily logs
                List {
                    ForEach(dailyLogs, id: \.date) { dayLog in
                        DailyLogRow(
                            date: dayLog.date,
                            logCount: dayLog.logCount,
                            errorCount: dayLog.errorCount,
                            warningCount: dayLog.warningCount
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copyDayLogsToClipboard(for: dayLog.date)
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
    
    private func copyDayLogsToClipboard(for date: Date) {
        let calendar = Calendar.current
        let sessions = logManager.getAllSessions().filter { session in
            calendar.isDate(session.startTime, inSameDayAs: date)
        }
        
        let combinedLogs = sessions
            .sorted { $0.startTime < $1.startTime }
            .map { logManager.getFormattedSessionLogs($0) }
            .joined(separator: "\n\n")
        
        UIPasteboard.general.string = combinedLogs
        copiedAlertType = .sessionLogs
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

struct DailyLogRow: View {
    let date: Date
    let logCount: Int
    let errorCount: Int
    let warningCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formattedDate(date))
                .font(.headline)
            
            HStack(spacing: 12) {
                Label("\(logCount) logs", systemImage: "doc.text")
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
        .padding(.vertical, 8)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}
