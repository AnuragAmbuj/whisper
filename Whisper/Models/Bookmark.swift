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
    var id: UUID
    var date: Date
    var pageOrLocation: Int // Simplified representation of location
    var note: String?
    
    // Relationship back to Book (optional or implicit)
    // For this simple app, we might just store bookmarks in the Book model as an array if SwiftData supports it easily,
    // or keep them separate. Let's start with embedded logic or separate if needed.
    // Ideally: var book: Book?
    
    init(date: Date = Date(), pageOrLocation: Int, note: String? = nil) {
        self.id = UUID()
        self.date = date
        self.pageOrLocation = pageOrLocation
        self.note = note
    }
}
