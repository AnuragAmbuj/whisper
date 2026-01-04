//
//  Book.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData

@Model
final class Book {
  var id: UUID
  var title: String
  var author: String
  var coverImageName: String
  var content: String
  var lastReadDate: Date
  var progress: Double  // 0.0 to 1.0

  // New properties for Phase 5
  var format: BookFormat = BookFormat.text
  var url: URL?  // Local file URL
  var sampleImages: [String] = []  // For mock comics

  @Relationship(deleteRule: .cascade) var bookmarks: [Bookmark] = []

  init(
    id: UUID = UUID(), title: String, author: String, coverImageName: String, content: String,
    lastReadDate: Date = Date(), progress: Double = 0.0, format: BookFormat = .text,
    url: URL? = nil, sampleImages: [String] = []
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.coverImageName = coverImageName
    self.content = content
    self.lastReadDate = lastReadDate
    self.progress = progress
    self.format = format
    self.url = url
    self.sampleImages = sampleImages
  }
}

enum BookFormat: String, Codable {
  case text
  case pdf
  case comic  // CBR/CBZ (Mocked via images)
  case epub
}
