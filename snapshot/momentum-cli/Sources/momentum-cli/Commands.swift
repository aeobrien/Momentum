import ArgumentParser
import Foundation

@main
struct MomentumCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "momentum-cli",
        abstract: "Read-only CLI for Momentum habit tracker data.",
        subcommands: [Status.self, Routines.self, History.self, Overdue.self, Export.self]
    )
}

// MARK: - Status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Quick-glance overview: overdue tasks, upcoming tasks, and routine summary."
    )

    func run() throws {
        let data = try DataLoader.load()
        let now = Date()

        printSourceBanner(data)

        // --- Overdue tasks ---
        let overdue = data.tasks
            .filter { task in
                guard let due = task.nextDueDate else { return false }
                return due < now
            }
            .sorted { ($0.nextDueDate ?? .distantPast) < ($1.nextDueDate ?? .distantPast) }

        if !overdue.isEmpty {
            let today = overdue.filter { Formatters.daysOverdue($0.nextDueDate!, now: now) == 0 }
            let thisWeek = overdue.filter {
                let d = Formatters.daysOverdue($0.nextDueDate!, now: now)
                return d >= 1 && d <= 7
            }
            let thisMonth = overdue.filter {
                let d = Formatters.daysOverdue($0.nextDueDate!, now: now)
                return d > 7 && d <= 30
            }
            let older = overdue.filter { Formatters.daysOverdue($0.nextDueDate!, now: now) > 30 }

            print("\n\u{1B}[1;31mOverdue Tasks (\(overdue.count))\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 60))

            if !today.isEmpty {
                print("  \u{1B}[1mDue today:\u{1B}[0m")
                for t in today { printTaskLine(t, now: now) }
            }
            if !thisWeek.isEmpty {
                print("  \u{1B}[1mThis week:\u{1B}[0m")
                for t in thisWeek { printTaskLine(t, now: now) }
            }
            if !thisMonth.isEmpty {
                print("  \u{1B}[1mThis month:\u{1B}[0m")
                for t in thisMonth { printTaskLine(t, now: now) }
            }
            if !older.isEmpty {
                print("  \u{1B}[1mOlder:\u{1B}[0m")
                for t in older { printTaskLine(t, now: now) }
            }
        } else {
            print("\n\u{1B}[32mNo overdue tasks!\u{1B}[0m")
        }

        // --- Upcoming tasks (next 7 days) ---
        let upcoming = data.tasks
            .filter { task in
                guard let due = task.nextDueDate else { return false }
                let days = Formatters.daysOverdue(due, now: now)
                return days < 0 && days >= -7
            }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }

        if !upcoming.isEmpty {
            print("\n\u{1B}[1;33mUpcoming (next 7 days: \(upcoming.count))\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 60))
            for t in upcoming {
                let rel = Formatters.relativeDays(from: t.nextDueDate!, to: now)
                let interval = Formatters.formatInterval(t.repetitionInterval)
                print("    \(Formatters.padRight(Formatters.truncate(t.taskName, to: 35), to: 37)) \(Formatters.padRight(rel, to: 14)) \(interval)")
            }
        }

        // --- Routine summary ---
        if !data.routines.isEmpty {
            print("\n\u{1B}[1;36mRoutines\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 60))
            print("  \(Formatters.padRight("Name", to: 20)) \(Formatters.padLeft("Completions", to: 12)) \(Formatters.padLeft("Last used", to: 16))")
            print("  \(String(repeating: "\u{2500}", count: 50))")
            for r in data.routines.sorted(by: { $0.totalCompletions > $1.totalCompletions }) {
                let lastUsed: String
                if let lu = r.lastUsed {
                    lastUsed = Formatters.relativeDays(from: lu, to: now)
                } else {
                    lastUsed = "never"
                }
                print("  \(Formatters.padRight(Formatters.truncate(r.name, to: 18), to: 20)) \(Formatters.padLeft("\(r.totalCompletions)", to: 12)) \(Formatters.padLeft(lastUsed, to: 16))")
            }
        }

        print()
    }

    private func printTaskLine(_ t: Task, now: Date) {
        let days = Formatters.daysOverdue(t.nextDueDate!, now: now)
        let daysStr = days == 0 ? "today" : "\(days)d overdue"
        let interval = Formatters.formatInterval(t.repetitionInterval)
        print("    \(Formatters.padRight(Formatters.truncate(t.taskName, to: 35), to: 37)) \(Formatters.padRight(daysStr, to: 14)) \(interval)")
    }
}

// MARK: - Routines

struct Routines: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show all routines with their tasks in order."
    )

    func run() throws {
        let data = try DataLoader.load()
        let now = Date()
        let taskMap = Dictionary(uniqueKeysWithValues: data.tasks.map { ($0.uuid, $0) })

        printSourceBanner(data)

        for routine in data.routines.sorted(by: { $0.name < $1.name }) {
            let lastUsed: String
            if let lu = routine.lastUsed {
                lastUsed = "\(Formatters.formatDate(lu)) (\(Formatters.relativeDays(from: lu, to: now)))"
            } else {
                lastUsed = "never"
            }

            print("\n\u{1B}[1;36m\(routine.name)\u{1B}[0m")
            print("  Completions: \(routine.totalCompletions)  |  Avg time: \(Formatters.formatDuration(routine.averageCompletionTime))  |  Last used: \(lastUsed)")
            print("  \(Formatters.padRight("Task", to: 35)) \(Formatters.padRight("Duration", to: 12)) \(Formatters.padRight("Interval", to: 16)) Last completed")
            print("  \(String(repeating: "\u{2500}", count: 85))")

            for taskID in routine.taskUUIDs {
                guard let t = taskMap[taskID] else {
                    print("  \u{1B}[2m  [missing task \(taskID.prefix(8))...]\u{1B}[0m")
                    continue
                }
                let duration = Formatters.formatDurationRange(min: t.minDuration, max: t.maxDuration)
                let interval = Formatters.formatInterval(t.repetitionInterval)
                let lastCompleted: String
                if let lc = t.lastCompleted {
                    lastCompleted = Formatters.relativeDays(from: lc, to: now)
                } else {
                    lastCompleted = "never"
                }
                print("  \(Formatters.padRight(Formatters.truncate(t.taskName, to: 33), to: 35)) \(Formatters.padRight(duration, to: 12)) \(Formatters.padRight(interval, to: 16)) \(lastCompleted)")
            }
        }
        print()
    }
}

// MARK: - History

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show completion history grouped by day."
    )

    @Option(name: .long, help: "Number of days to show (default: 7)")
    var days: Int = 7

    func run() throws {
        let data = try DataLoader.load()
        let now = Date()
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!

        let taskMap = Dictionary(uniqueKeysWithValues: data.tasks.map { ($0.uuid, $0) })

        printSourceBanner(data)

        // Filter and group by day
        let recent = data.completionHistory
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }

        if recent.isEmpty {
            print("\nNo completions in the last \(days) days.")
            print()
            return
        }

        // Group by calendar day
        var grouped: [(Date, [CompletionEntry])] = []
        var currentDay: Date? = nil
        var currentEntries: [CompletionEntry] = []

        for entry in recent {
            let day = calendar.startOfDay(for: entry.date)
            if day != currentDay {
                if let cd = currentDay {
                    grouped.append((cd, currentEntries))
                }
                currentDay = day
                currentEntries = [entry]
            } else {
                currentEntries.append(entry)
            }
        }
        if let cd = currentDay {
            grouped.append((cd, currentEntries))
        }

        print("\n\u{1B}[1mCompletion History (last \(days) days)\u{1B}[0m")

        for (day, entries) in grouped {
            let totalTime = entries.reduce(0.0) { $0 + $1.duration }
            print("\n\u{1B}[1;33m\(Formatters.formatDay(day))\u{1B}[0m  (\(entries.count) tasks, \(Formatters.formatDuration(totalTime)) total)")
            print(String(repeating: "\u{2500}", count: 60))

            for entry in entries.sorted(by: { $0.date < $1.date }) {
                let name = taskMap[entry.taskUUID]?.taskName ?? "Unknown task"
                let time = Formatters.formatTime(entry.date)
                let dur = Formatters.formatDuration(entry.duration)
                print("  \(time)  \(Formatters.padRight(Formatters.truncate(name, to: 38), to: 40)) \(dur)")
            }
        }
        print()
    }
}

// MARK: - Overdue

struct Overdue: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Detailed view of all overdue tasks sorted by days overdue."
    )

    func run() throws {
        let data = try DataLoader.load()
        let now = Date()

        printSourceBanner(data)

        let overdue = data.tasks
            .filter { task in
                guard let due = task.nextDueDate else { return false }
                return due < now
            }
            .sorted { (a, b) in
                let daysA = Formatters.daysOverdue(a.nextDueDate!, now: now)
                let daysB = Formatters.daysOverdue(b.nextDueDate!, now: now)
                return daysA > daysB
            }

        if overdue.isEmpty {
            print("\n\u{1B}[32mNo overdue tasks!\u{1B}[0m\n")
            return
        }

        print("\n\u{1B}[1;31mOverdue Tasks (\(overdue.count))\u{1B}[0m")
        print()
        print("  \(Formatters.padRight("Task", to: 32)) \(Formatters.padLeft("Overdue", to: 10)) \(Formatters.padRight("Interval", to: 16)) \(Formatters.padRight("Due date", to: 14)) \(Formatters.padRight("Last done", to: 14)) Priority")
        print("  \(String(repeating: "\u{2500}", count: 100))")

        for t in overdue {
            let days = Formatters.daysOverdue(t.nextDueDate!, now: now)
            let daysStr = days == 0 ? "today" : "\(days)d"
            let interval = Formatters.formatInterval(t.repetitionInterval)
            let dueDate = Formatters.formatDate(t.nextDueDate!)
            let lastDone: String
            if let lc = t.lastCompleted {
                lastDone = Formatters.formatDate(lc)
            } else {
                lastDone = "never"
            }
            let priority = Formatters.essentialityLabel(t.essentiality)
            print("  \(Formatters.padRight(Formatters.truncate(t.taskName, to: 30), to: 32)) \(Formatters.padLeft(daysStr, to: 10)) \(Formatters.padRight(interval, to: 16)) \(Formatters.padRight(dueDate, to: 14)) \(Formatters.padRight(lastDone, to: 14)) \(priority)")
        }
        print()
    }
}

// MARK: - Export

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Full JSON dump to stdout."
    )

    func run() throws {
        let rawData = try DataLoader.loadRawJSON()
        // Pretty-print the JSON
        if let json = try? JSONSerialization.jsonObject(with: rawData),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            print(str)
        } else if let str = String(data: rawData, encoding: .utf8) {
            print(str)
        }
    }
}

// MARK: - Helpers

func printSourceBanner(_ data: MomentumData) {
    let sourceInfo: String
    if let date = data.sourceDate {
        sourceInfo = "\(data.source.rawValue) (\(Formatters.formatDate(date)))"
    } else {
        sourceInfo = data.source.rawValue
    }
    print("\u{1B}[2mSource: \(sourceInfo) | \(data.tasks.count) tasks, \(data.routines.count) routines, \(data.completionHistory.count) completions\u{1B}[0m")
}
