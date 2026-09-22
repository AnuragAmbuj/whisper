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
  var id: UUID = UUID()
  var title: String = ""
  var author: String = ""
  var coverImageName: String = ""
  var content: String = ""
  var lastReadDate: Date = Date()
  var progress: Double = 0.0  // 0.0 to 1.0

  // Optional to safely deserialize legacy database records where format was NULL
  var format: BookFormat? = BookFormat.text
  var url: URL? = nil  // Local file URL
  var sampleImages: [String] = []  // For mock comics

  @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
  var bookmarks: [Bookmark]? = []

  var safeBookmarks: [Bookmark] {
    get { bookmarks ?? [] }
    set { bookmarks = newValue }
  }

  var bookDir: URL? {
    let currentFormat = format ?? .text
    guard currentFormat == .epub || currentFormat == .comic else { return url }
    
    // 1. If explicit URL exists on disk, use it
    if let url = url, FileManager.default.fileExists(atPath: url.path) {
      return url
    }
    
    // 2. Resolve inside standard documents directory for epub/comic
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return url }
    
    let path = docs.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    if FileManager.default.fileExists(atPath: path.path) {
      return path
    }
    
    return path
  }

  init(
    id: UUID = UUID(),
    title: String = "",
    author: String = "",
    coverImageName: String = "",
    content: String = "",
    lastReadDate: Date = Date(),
    progress: Double = 0.0,
    format: BookFormat? = .text,
    url: URL? = nil,
    sampleImages: [String] = []
  ) {
    self.id = id
    self.title = title
    self.author = author
    self.coverImageName = coverImageName
    self.content = content
    self.lastReadDate = lastReadDate
    self.progress = progress
    self.format = format ?? .text
    self.url = url
    self.sampleImages = sampleImages
    self.bookmarks = []
  }

  func addBookmark(_ bookmark: Bookmark) {
    if bookmarks == nil {
      bookmarks = []
    }
    bookmark.book = self
    bookmarks?.append(bookmark)
  }

  /// Deletes all files associated with this book (EPUB directory, cover image)
  func cleanupFiles() {
    let fileManager = FileManager.default

    // Delete extracted book directory
    if let dir = bookDir {
      try? fileManager.removeItem(at: dir)
    } else if let fileURL = url, fileURL.isFileURL {
      try? fileManager.removeItem(at: fileURL)
    }

    // Delete cover image
    if !coverImageName.isEmpty {
      if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let coverURL = docs.appendingPathComponent(coverImageName)
        try? fileManager.removeItem(at: coverURL)
      }
    }
  }
}

enum BookFormat: String, Codable {
  case text
  case pdf
  case comic  // CBR/CBZ (Mocked via images)
  case epub

  var displayName: String {
    switch self {
    case .text: return "Plain Text"
    case .pdf: return "PDF Document"
    case .comic: return "Comic Book"
    case .epub: return "EPUB Book"
    }
  }

  var iconName: String {
    switch self {
    case .text: return "doc.text"
    case .pdf: return "doc.richtext"
    case .comic: return "photo.on.rectangle.angled"
    case .epub: return "book"
    }
  }
}
