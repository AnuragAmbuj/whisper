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


enum BookSyncStatus: Equatable {
  case synced
  case syncing
  case pending
  case failed(String)
  case localOnly

  var iconName: String {
    switch self {
    case .synced: return "checkmark.icloud.fill"
    case .syncing: return "arrow.triangle.2.circlepath"
    case .pending: return "icloud.and.arrow.up"
    case .failed: return "exclamationmark.icloud.fill"
    case .localOnly: return "internaldrive"
    }
  }

  var displayText: String {
    switch self {
    case .synced: return "Synced"
    case .syncing: return "Syncing..."
    case .pending: return "Pending Sync"
    case .failed(let err): return "Sync Error: \(err)"
    case .localOnly: return "On Device"
    }
  }
}

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
  var url: URL? = nil  // Local or cloud file URL
  var sampleImages: [String] = []  // For mock comics

  // Cloud Synchronization Status
  var cloudFileID: String? = nil
  var isCloudSynced: Bool = false
  var cloudSyncError: String? = nil
  var cloudSyncDate: Date? = nil

  @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
  var bookmarks: [Bookmark]? = []

  var safeBookmarks: [Bookmark] {
    get { bookmarks ?? [] }
    set { bookmarks = newValue }
  }

  /// Resolves the actual reachable file URL across devices (iPhone, iPad, Mac)
  /// Checks local container path, fallback documents directory by filename, and iCloud Drive.
  var resolvedURL: URL? {
    let fileManager = FileManager.default
    
    // 1. Direct file existence check
    if let url = url, fileManager.fileExists(atPath: url.path) {
      return url
    }
    
    // 2. Resolve inside local Documents/Books directory by filename
    if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      let booksDir = docs.appendingPathComponent("Books", isDirectory: true)
      if let fileName = url?.lastPathComponent, !fileName.isEmpty {
        let localCandidate = booksDir.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: localCandidate.path) {
          return localCandidate
        }
      }
    }
    
    // 3. Resolve inside iCloud Drive Ubiquity Container Documents/Books
    if let cloudDocs = CloudSyncService.resolvedUbiquityDocumentsURL {
      let cloudBooksDir = cloudDocs.appendingPathComponent("Books", isDirectory: true)
      if let fileName = url?.lastPathComponent, !fileName.isEmpty {
        let cloudCandidate = cloudBooksDir.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: cloudCandidate.path) {
          return cloudCandidate
        }
      }
    }
    
    return url
  }

  /// Resolves the directory for reading unpacked EPUB or Comic books.
  /// If the unpacked cache is missing on this device (e.g. freshly synced to iPad),
  /// it automatically unpacks the archive file into the local sandbox on demand.
  var bookDir: URL? {
    let currentFormat = format ?? .text
    guard currentFormat == .epub || currentFormat == .comic else { return resolvedURL }
    let fileManager = FileManager.default
    
    // 1. If explicit URL exists on disk and is a directory
    if let url = url, fileManager.fileExists(atPath: url.path) {
      var isDir: ObjCBool = false
      if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
        return url
      }
    }
    
    // 2. Resolve inside standard documents directory for epub/comic
    guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return resolvedURL }
    
    let path = docs.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    if fileManager.fileExists(atPath: path.path) {
      return path
    }
    
    // 3. Auto-unpack from archive file (e.g. synced from iCloud or local) if unzipped cache is missing
    if let archiveURL = resolvedURL, fileManager.fileExists(atPath: archiveURL.path) {
      var isDir: ObjCBool = false
      if !fileManager.fileExists(atPath: archiveURL.path, isDirectory: &isDir) || !isDir.boolValue {
        try? fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        try? MiniZip.shared.unzip(sourceURL: archiveURL, destinationURL: path)
        if fileManager.fileExists(atPath: path.path) {
          return path
        }
      }
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
    sampleImages: [String] = [],
    cloudFileID: String? = nil,
    isCloudSynced: Bool = false,
    cloudSyncError: String? = nil,
    cloudSyncDate: Date? = nil
  ) {
    self.cloudFileID = cloudFileID
    self.isCloudSynced = isCloudSynced
    self.cloudSyncError = cloudSyncError
    self.cloudSyncDate = cloudSyncDate
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

  func removeBookmark(_ bookmark: Bookmark) {
    bookmarks?.removeAll { $0.id == bookmark.id }
  }

  // MARK: - Searchable Text Resolution for Smart AI Find

  /// Resolves the actual full body text of the book across formats
  /// - Text: returns `content` or raw file content
  /// - EPUB: reads all chapter HTML/XHTML files from `bookDir` and strips tags
  /// - PDF: reads all text from `PDFDocument` pages
  func resolveSearchableContent() -> String {
    // 1. Text format: read from file if available, or return stored content
    if format == .text {
      if let fileURL = resolvedURL,
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
    if format == .pdf, let pdfURL = resolvedURL, FileManager.default.fileExists(atPath: pdfURL.path) {
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
    } else if let fileURL = resolvedURL, fileURL.isFileURL {
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
    case .epub: return "book.closed"
    }
  }
}
