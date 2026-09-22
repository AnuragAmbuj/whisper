//
//  Book.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData
#if canImport(PDFKit)
import PDFKit
#endif

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

  /// Resolves the actual text content of the book across all formats (EPUB, PDF, Text, etc.)
  /// Enables TypeSafe AI semantic search, character extraction, and summarization to operate
  /// on the true book text rather than brief metadata summaries.
  func resolveSearchableContent() -> String {
    // 1. Plain Text format
    if format == .text || format == nil {
      if !content.isEmpty && content.count > 60 {
        return content
      }
      if let fileURL = url,
         let fileContent = try? String(contentsOf: fileURL, encoding: .utf8),
         !fileContent.isEmpty {
        return fileContent
      }
      return content
    }

    // 2. EPUB format: read all chapter html files from bookDir
    if format == .epub, let dir = bookDir {
      var chapterPaths: [String] = []
      let spineURL = dir.appendingPathComponent("spine.json")
      if let spineData = try? Data(contentsOf: spineURL),
         let decoded = try? JSONDecoder().decode([String].self, from: spineData) {
        chapterPaths = decoded
      }

      if chapterPaths.isEmpty {
        let ch1 = dir.appendingPathComponent("chapter1.html")
        let ch2 = dir.appendingPathComponent("chapter2.html")
        if FileManager.default.fileExists(atPath: ch1.path) { chapterPaths.append("chapter1.html") }
        if FileManager.default.fileExists(atPath: ch2.path) { chapterPaths.append("chapter2.html") }
      }

      if chapterPaths.isEmpty {
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
          while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent.lowercased()
            if (ext == "html" || ext == "xhtml" || ext == "htm"),
               !name.contains("toc"), !name.contains("nav"), !name.hasPrefix(".") {
              chapterPaths.append(fileURL.path.replacingOccurrences(of: dir.path + "/", with: ""))
            }
          }
        }
      }

      var extractedParagraphs: [String] = []
      for path in chapterPaths {
        let fullURL = dir.appendingPathComponent(path)
        if let html = try? String(contentsOf: fullURL, encoding: .utf8) {
          let stripped = html
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

          let cleanLines = stripped.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 15 }

          if !cleanLines.isEmpty {
            extractedParagraphs.append(contentsOf: cleanLines)
          }
        }
      }

      if !extractedParagraphs.isEmpty {
        return extractedParagraphs.joined(separator: "\n\n")
      }
    }

    // 3. PDF format: extract text from pages
    if format == .pdf, let pdfURL = url, FileManager.default.fileExists(atPath: pdfURL.path) {
      #if canImport(PDFKit)
      if let doc = PDFDocument(url: pdfURL) {
        var pagesText: [String] = []
        for i in 0..<min(doc.pageCount, 100) {
          if let page = doc.page(at: i),
             let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
             !text.isEmpty {
            pagesText.append(text)
          }
        }
        if !pagesText.isEmpty {
          return pagesText.joined(separator: "\n\n")
        }
      }
      #endif
    }

    // Fallback: existing content or title + author
    return content.isEmpty ? "\(title) by \(author)" : content
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
