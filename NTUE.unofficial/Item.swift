//
//  Item.swift
//  NTUE.unofficial
//
//  Created by Ray Hsu on 2026/6/29.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
