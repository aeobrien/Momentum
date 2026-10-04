// LogSession.swift
import Foundation

struct LogSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date?  // Changed from let to var
    var records: [LogRecord]
    var timeBlock: TimeBlock
    
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    init(id: UUID = UUID(), startTime: Date = Date(), endTime: Date? = nil, records: [LogRecord] = []) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.records = records
        self.timeBlock = TimeBlock.from(date: startTime)
    }
}

// New TimeBlock enum
enum TimeBlock: Int, Codable, CaseIterable {
    case midnight = 0   // 00:00 - 02:00
    case earlyMorning   // 02:00 - 04:00
    case dawn           // 04:00 - 06:00
    case morning        // 06:00 - 08:00
    case lateMorning    // 08:00 - 10:00
    case noon          // 10:00 - 12:00
    case earlyAfternoon // 12:00 - 14:00
    case afternoon     // 14:00 - 16:00
    case evening       // 16:00 - 18:00
    case lateEvening   // 18:00 - 20:00
    case night         // 20:00 - 22:00
    case lateNight     // 22:00 - 00:00
    
    static func from(date: Date) -> TimeBlock {
        let hour = Calendar.current.component(.hour, from: date)
        return TimeBlock(rawValue: hour / 2) ?? .midnight
    }
    
    var timeRange: String {
        let startHour = rawValue * 2
        let endHour = startHour + 2
        return String(format: "%02d:00-%02d:00", startHour, endHour)
    }
}
