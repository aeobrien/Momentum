import HealthKit
import Foundation

// MARK: - Health Data Models

struct HealthDaySummary: Codable {
    var date: Date
    var meditationMinutes: Int = 0
    var meditationSessions: Int = 0
    var steps: Int = 0
    var walkingDistanceKm: Double = 0
    var activeEnergyKcal: Int = 0
    var exerciseMinutes: Int = 0
    /// Sleep ending on this date. Nil means sleep was not available, not zero.
    var sleepMinutes: Int?
}

struct HealthSummary: Codable {
    var lastUpdated: Date
    var last30Days: [HealthDaySummary]
}

// MARK: - HealthKitReader

class HealthKitReader {
    static let shared = HealthKitReader()
    private let healthStore = HKHealthStore()

    // Types we want to read
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
    ]

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, nil)
            return
        }
        healthStore.requestAuthorization(toShare: nil, read: readTypes, completion: completion)
    }

    // Fetch last 30 days of health data
    func fetchLast30Days(completion: @escaping ([HealthDaySummary]) -> Void) {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -29, to: endDate) else {
            completion([])
            return
        }

        // Build array of dates
        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        let group = DispatchGroup()
        var summaries: [HealthDaySummary] = []
        let lock = NSLock()

        for date in dates {
            group.enter()
            fetchDaySummary(for: date) { summary in
                lock.lock()
                summaries.append(summary)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(summaries.sorted { $0.date < $1.date })
        }
    }

    private func fetchDaySummary(for date: Date, completion: @escaping (HealthDaySummary) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        var summary = HealthDaySummary(date: startOfDay)
        let group = DispatchGroup()

        // Steps
        group.enter()
        fetchSum(quantityType: .stepCount, unit: .count(), predicate: predicate) { value in
            summary.steps = Int(value)
            group.leave()
        }

        // Walking distance
        group.enter()
        fetchSum(quantityType: .distanceWalkingRunning, unit: .meterUnit(with: .kilo), predicate: predicate) { value in
            summary.walkingDistanceKm = round(value * 10) / 10
            group.leave()
        }

        // Active energy
        group.enter()
        fetchSum(quantityType: .activeEnergyBurned, unit: .kilocalorie(), predicate: predicate) { value in
            summary.activeEnergyKcal = Int(value)
            group.leave()
        }

        // Exercise minutes
        group.enter()
        fetchSum(quantityType: .appleExerciseTime, unit: .minute(), predicate: predicate) { value in
            summary.exerciseMinutes = Int(value)
            group.leave()
        }

        // Meditation (category type - need different query)
        group.enter()
        fetchMindfulMinutes(predicate: predicate) { minutes, sessions in
            summary.meditationMinutes = Int(minutes)
            summary.meditationSessions = sessions
            group.leave()
        }


        // Sleep is assigned to the day on which it ends. The noon-to-noon
        // window avoids splitting an overnight sleep at midnight.
        group.enter()
        fetchSleepMinutes(endingOn: startOfDay) { minutes in
            summary.sleepMinutes = minutes
            group.leave()
        }

        group.notify(queue: .global()) {
            completion(summary)
        }
    }

    private func fetchSum(quantityType identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate, completion: @escaping (Double) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion(0)
            return
        }
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            completion(value)
        }
        healthStore.execute(query)
    }

    private func fetchMindfulMinutes(predicate: NSPredicate, completion: @escaping (Double, Int) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            completion(0, 0)
            return
        }
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            guard let samples = samples else {
                completion(0, 0)
                return
            }
            var totalMinutes: Double = 0
            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                totalMinutes += duration
            }
            completion(totalMinutes, samples.count)
        }
        healthStore.execute(query)
    }

    private func fetchSleepMinutes(endingOn date: Date, completion: @escaping (Int?) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }

        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .hour, value: 12, to: date),
              let start = calendar.date(byAdding: .day, value: -1, to: end) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in
            guard error == nil, let categorySamples = samples as? [HKCategorySample] else {
                completion(nil)
                return
            }

            // Sleep Cycle and Apple Watch can record the same period. Merge
            // overlapping asleep intervals so that time is not counted twice.
            let intervals = categorySamples
                .filter { self.isAsleepValue($0.value) }
                .map { (max($0.startDate, start), min($0.endDate, end)) }
                .filter { $0.1 > $0.0 }
                .sorted { $0.0 < $1.0 }

            guard !intervals.isEmpty else {
                completion(nil)
                return
            }

            var merged: [(Date, Date)] = []
            for interval in intervals {
                if let last = merged.last, interval.0 <= last.1 {
                    merged[merged.count - 1].1 = max(last.1, interval.1)
                } else {
                    merged.append(interval)
                }
            }

            let minutes = merged.reduce(0.0) {
                $0 + $1.1.timeIntervalSince($1.0) / 60.0
            }
            completion(Int(minutes.rounded()))
        }
        healthStore.execute(query)
    }

    private func isAsleepValue(_ value: Int) -> Bool {
        if #available(iOS 16.0, *) {
            return [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            ].contains(value)
        }
        return value == HKCategoryValueSleepAnalysis.asleep.rawValue
    }
}
