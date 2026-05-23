//
//  Item.swift
//  Blissful Catholic
//
//  Created by Jesus Flores on 5/23/26.
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
