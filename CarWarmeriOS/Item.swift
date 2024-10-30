//
//  Item.swift
//  CarWarmeriOS
//
//  Created by Mathew Kirby on 10/30/24.
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
