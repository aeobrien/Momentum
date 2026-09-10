import Foundation

enum Formatters {

    // MARK: - Duration Formatting

    /// Format seconds into human-readable duration (e.g., "5m", "1h 30m", "2h")
    static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    /// Format a repetition interval in seconds to human-readable (e.g., "every day", "every 3 days")
    static func formatInterval(_ seconds: Int) -> String {
        if seconds <= 0 { return "no repeat" }

        let hours = seconds / 3600
        let days = seconds / 86400
        let weeks = seconds / 604800

        if seconds < 3600 {
            let mins = seconds / 60
            return mins == 1 ? "every minute" : "every \(mins) minutes"
        } else if seconds < 86400 {
            return hours == 1 ? "every hour" : "every \(hours) hours"
        } else if seconds < 604800 {
            if days == 1 { return "every day" }
            return "every \(days) days"
        } else if seconds < 2592000 {
            if weeks == 1 { return "every week" }
            return "every \(weeks) weeks"
        } else {
            let months = seconds / 2592000
            if months == 1 { return "every month" }
            return "every \(months) months"
        }
    }

    /// Format a duration range (min-max) for task display
    static func formatDurationRange(min: Int, max: Int) -> String {
        if min == max {
            return formatDuration(Double(min))
        }
        return "\(formatDuration(Double(min)))-\(formatDuration(Double(max)))"
    }

    // MARK: - Date Formatting

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, dd MMM yyyy"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func formatDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func formatDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "3 days ago", "today", "in 2 days"
    static func relativeDays(from date: Date, to now: Date = Date()) -> String {
        let calendar = Calendar.current
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0

        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days > 1 { return "\(days) days ago" }
        if days == -1 { return "tomorrow" }
        return "in \(-days) days"
    }

    static func daysOverdue(_ date: Date, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0
    }

    // MARK: - Essentiality

    static func essentialityLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Essential"
        case 2: return "Important"
        case 3: return "Optional"
        default: return "Level \(level)"
        }
    }

    // MARK: - Table Helpers

    static func padRight(_ string: String, to width: Int) -> String {
        if string.count >= width { return string }
        return string + String(repeating: " ", count: width - string.count)
    }

    static func padLeft(_ string: String, to width: Int) -> String {
        if string.count >= width { return string }
        return String(repeating: " ", count: width - string.count) + string
    }

    static func truncate(_ string: String, to maxWidth: Int) -> String {
        if string.count <= maxWidth { return string }
        return String(string.prefix(maxWidth - 1)) + "\u{2026}"
    }
}
