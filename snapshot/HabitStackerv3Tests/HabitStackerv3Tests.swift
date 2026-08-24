//
//  HabitStackerv3Tests.swift
//  HabitStackerv3Tests
//
//  Created by Aidan O'Brien on 23/10/2024.
//

import XCTest
import CoreData
@testable import Momentum

final class MomentumTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testCompletingRoutineIncrementsLifetimeCountOnce() throws {
        let model = try XCTUnwrap(
            NSManagedObjectModel.mergedModel(from: [Bundle(for: CDRoutine.self)])
        )
        let container = NSPersistentContainer(name: "Momentum 3", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        let storeLoaded = expectation(description: "in-memory store loaded")
        var storeLoadError: Error?
        container.loadPersistentStores { _, error in
            storeLoadError = error
            storeLoaded.fulfill()
        }
        wait(for: [storeLoaded], timeout: 2)
        XCTAssertNil(storeLoadError)

        let context = container.viewContext
        let routine = CDRoutine(context: context)
        routine.uuid = UUID()
        routine.name = "Hygiene"
        routine.totalCompletions = 4
        let previousLastUsed = Date(timeIntervalSinceNow: -86_400)
        routine.lastUsed = previousLastUsed

        let task = CDTask(context: context)
        task.uuid = UUID()
        task.taskName = "Brush teeth"
        task.minDuration = 1
        task.maxDuration = 1
        task.shouldTrackAverageTime = false

        let runner = RoutineRunner(
            context: context,
            routine: routine,
            schedule: [ScheduledTask(task: task, allocatedDuration: 60)]
        )

        runner.markTaskComplete()
        context.performAndWait {}

        XCTAssertEqual(routine.totalCompletions, 5)
        XCTAssertGreaterThan(try XCTUnwrap(routine.lastUsed), previousLastUsed)
    }

}
