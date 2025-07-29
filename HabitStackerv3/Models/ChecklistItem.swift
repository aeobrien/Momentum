//
//  ChecklistItem.swift
//  Momentum
//
//  Created on 28/07/2025.
//

import Foundation

@objc(ChecklistItem)
public class ChecklistItem: NSObject, NSSecureCoding, Codable, Identifiable {
    public static var supportsSecureCoding: Bool = true
    
    @objc public var id: UUID
    @objc public var title: String
    @objc public var isCompleted: Bool
    @objc public var order: Int
    
    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false, order: Int = 0) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
        super.init()
    }
    
    // NSSecureCoding
    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(title, forKey: "title")
        coder.encode(isCompleted, forKey: "isCompleted")
        coder.encode(order, forKey: "order")
    }
    
    public required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSUUID.self, forKey: "id") as UUID?,
              let title = coder.decodeObject(of: NSString.self, forKey: "title") as String? else {
            return nil
        }
        self.id = id
        self.title = title
        self.isCompleted = coder.decodeBool(forKey: "isCompleted")
        self.order = Int(coder.decodeInt32(forKey: "order"))
        super.init()
    }
    
    // Codable
    private enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, order
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(order, forKey: .order)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.order = try container.decode(Int.self, forKey: .order)
        super.init()
    }
    
    public override var description: String {
        return "ChecklistItem(id: \(id), title: \(title), isCompleted: \(isCompleted), order: \(order))"
    }
}

extension ChecklistItem {
    public static func == (lhs: ChecklistItem, rhs: ChecklistItem) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title && lhs.isCompleted == rhs.isCompleted && lhs.order == rhs.order
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ChecklistItem else { return false }
        return self == other
    }
    
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(isCompleted)
        hasher.combine(order)
        return hasher.finalize()
    }
}
