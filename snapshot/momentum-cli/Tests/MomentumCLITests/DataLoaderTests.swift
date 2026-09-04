import XCTest
@testable import momentum_cli

final class DataLoaderTests: XCTestCase {
    func testParsesHealthSummaryFromSharedFile() throws {
        let json = """
        {
          "tasks": [],
          "routines": [],
          "completionHistory": [],
          "healthSummary": {
            "lastUpdated": "2026-08-22T09:30:00Z",
            "last30Days": [{
              "date": "2026-08-22T00:00:00Z",
              "meditationMinutes": 12,
              "meditationSessions": 1,
              "steps": 4321,
              "walkingDistanceKm": 3.4,
              "activeEnergyKcal": 321,
              "exerciseMinutes": 29,
              "sleepMinutes": 463
            }]
          },
          "lastModified": "2026-08-22T09:30:00Z",
          "lastModifiedBy": "app"
        }
        """

        let parsed = try DataLoader.parseSharedFile(Data(json.utf8))

        XCTAssertEqual(parsed.healthSummary?.last30Days.count, 1)
        XCTAssertEqual(parsed.healthSummary?.last30Days.first?.steps, 4321)
        XCTAssertEqual(parsed.healthSummary?.last30Days.first?.meditationMinutes, 12)
        XCTAssertEqual(parsed.healthSummary?.last30Days.first?.walkingDistanceKm, 3.4)
        XCTAssertEqual(parsed.healthSummary?.last30Days.first?.sleepMinutes, 463)
    }

    func testOlderHealthSummaryWithoutSleepStillParses() throws {
        let json = """
        {
          "tasks": [], "routines": [], "completionHistory": [],
          "healthSummary": {
            "lastUpdated": "2026-08-22T09:30:00Z",
            "last30Days": [{
              "date": "2026-08-22T00:00:00Z",
              "meditationMinutes": 0, "meditationSessions": 0,
              "steps": 10, "walkingDistanceKm": 0.1,
              "activeEnergyKcal": 1, "exerciseMinutes": 0
            }]
          },
          "lastModified": "2026-08-22T09:30:00Z",
          "lastModifiedBy": "app"
        }
        """

        let parsed = try DataLoader.parseSharedFile(Data(json.utf8))

        XCTAssertNil(parsed.healthSummary?.last30Days.first?.sleepMinutes)
    }

    func testOrdinaryLocalFileIsNotDataless() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("test".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(DataLoader.isDataless(url))
    }

    func testRelayCanBeDisabledForOfflineUse() {
        XCTAssertNil(DataLoader.relayURL(environment: ["MOMENTUM_DISABLE_RELAY": "1"]))
    }

    func testRelayURLCanBeOverriddenForTesting() {
        let url = DataLoader.relayURL(environment: [
            "MOMENTUM_RELAY_URL": "https://example.test/momentum.json"
        ])

        XCTAssertEqual(url?.absoluteString, "https://example.test/momentum.json")
    }
}
