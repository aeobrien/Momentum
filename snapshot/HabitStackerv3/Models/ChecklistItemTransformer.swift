//
//  ChecklistItemTransformer.swift
//  Momentum
//
//  Created on 28/07/2025.
//

import Foundation

@objc(ChecklistItemTransformer)
final class ChecklistItemTransformer: NSSecureUnarchiveFromDataTransformer {
    
    static let name = NSValueTransformerName(rawValue: "ChecklistItemTransformer")
    
    override static var allowedTopLevelClasses: [AnyClass] {
        // Include all the standard classes plus our custom ChecklistItem class
        return [NSArray.self, ChecklistItem.self, NSString.self, NSNumber.self, NSUUID.self]
    }
    
    static func register() {
        let transformer = ChecklistItemTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}