//
//  Item.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/12/25.
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
