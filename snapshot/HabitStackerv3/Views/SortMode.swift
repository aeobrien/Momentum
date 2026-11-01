//
//  SortMode.swift
//  HabitStackerv3
//
//  Created by Aidan O'Brien on 26/10/2024.
//

import Foundation
import SwiftUI

enum SortMode: String, CaseIterable {
    case nameAsc = "Name A-Z"
    case nameDesc = "Name Z-A"
    case essentialityDesc = "Most Essential"
    case essentialityAsc = "Least Essential"
    case timeDesc = "Longest First"
    case timeAsc = "Shortest First"
}
