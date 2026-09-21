//
//  Bookmark.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID = UUID()
    var date: Date = Date()
    var pageOrLocation: Int = 0
    var note: String? = nil
    
    // Relationship back to Book
    var book: Book? = nil
    
    init(id: UUID = UUID(), date: Date = Date(), pageOrLocation: Int = 0, note: String? = nil) {
        self.id = id
        self.date = date
        self.pageOrLocation = pageOrLocation
        self.note = note
    }
}
