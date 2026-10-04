//
//  ResultExtensions.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 23/10/2024.
//

import Foundation

extension Result {
    /// Returns the value if the result is a success, or the provided default value if it's a failure.
    func getOrElse(_ defaultValue: @autoclosure () -> Success) -> Success {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return defaultValue()
        }
    }
}
