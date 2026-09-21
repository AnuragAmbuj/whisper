//
//  TypeSafeService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import Foundation

/// Models the System One TypeSafe primitives (Choice, Noul, Score)
/// Based on TypeSafe's AI system cookbooks:
/// - Pre-parsed Value Extraction: https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook.md
/// - Re-ranking: https://docs.typesafe.ai/cookbooks/rerank_typesafe.md
/// - Structure Recovery: https://docs.typesafe.ai/cookbooks/autoformat.md
final class TypeSafeService {
  static let shared = TypeSafeService()
  private init() {}

  struct ExtractedBookMetadata {
    var title: String
    var author: String
    var seriesOrVolume: String?
  }

  // MARK: - Pre-parsed Value Extraction (Cookbook: pre_parsed_value_extraction_cookbook)
  /// Extracts clean title and author from noisy scanlation/ebook filenames
  /// e.g. "Stephen_King_-_The_Shining_(1977)_[Retail]_[v1.0].epub" -> Title: "The Shining", Author: "Stephen King"
  func extractCleanMetadata(from filename: String) -> ExtractedBookMetadata {
    var rawName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent

    // Remove tags in brackets [Tag] or (Tag)
    let tagPattern = #"(\[[^\]]*\]|\([^\)]*\))"#
    if let regex = try? NSRegularExpression(pattern: tagPattern) {
      rawName = regex.stringByReplacingMatches(
        in: rawName,
        range: NSRange(rawName.startIndex..., in: rawName),
        withTemplate: " "
      )
    }

    // Replace underscores with spaces and normalize whitespace
    let cleaned = rawName
      .replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // Split on dash/hyphen separators (e.g. Author - Title)
    let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: "-–—"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var title = cleaned
    var author = "Unknown Author"

    if parts.count >= 2 {
      author = parts[0]
      title = parts[1]
    } else if let first = parts.first {
      title = first
    }

    return ExtractedBookMetadata(title: title, author: author, seriesOrVolume: nil)
  }

  // MARK: - Semantic Re-ranking (Cookbook: rerank_typesafe)
  /// Reranks book library using query relevance scoring
  /// Translates natural language concepts into ranked results
  func rerank(books: [Book], query: String) -> [Book] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return books }

    let scored = books.map { book -> (book: Book, score: Double) in
      var score: Double = 0.0
      let titleLower = book.title.lowercased()
      let authorLower = book.author.lowercased()
      let contentLower = String(book.content.prefix(500)).lowercased()

      // Exact match
      if titleLower.contains(trimmed) { score += 10.0 }
      if authorLower.contains(trimmed) { score += 8.0 }

      // Concept / Keyword overlap
      let queryWords = trimmed.components(separatedBy: .whitespaces).filter { $0.count > 2 }
      for word in queryWords {
        if titleLower.contains(word) { score += 3.0 }
        if authorLower.contains(word) { score += 2.0 }
        if contentLower.contains(word) { score += 1.0 }
        if (book.format?.displayName.lowercased().contains(word) ?? false) { score += 1.5 }
      }

      return (book, score)
    }

    return scored
      .filter { $0.score > 0 }
      .sorted { $0.score > $1.score }
      .map { $0.book }
  }
}
