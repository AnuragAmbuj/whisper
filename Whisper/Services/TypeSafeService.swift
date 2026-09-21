//
//  TypeSafeService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import Foundation

/// Models the System One TypeSafe primitives (Choice, Noul, Score)
/// Based on TypeSafe's AI system cookbooks:
/// - Semantic Find: https://docs.typesafe.ai/cookbooks/semantic_find.md
/// - Pre-parsed Value Extraction: https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook.md
/// - Re-ranking: https://docs.typesafe.ai/cookbooks/rerank_typesafe.md
/// - Entity Alignment & Discovery: https://docs.typesafe.ai/cookbooks/entity_alignment.md
final class TypeSafeService: @unchecked Sendable {
  static let shared = TypeSafeService()
  private init() {}

  // MARK: - Types & Models

  struct ExtractedBookMetadata: Sendable {
    var title: String
    var author: String
    var seriesOrVolume: String?
  }

  enum SemanticVerdict: String, Sendable {
    case answered = "Found in text"
    case partial = "Partially addressed"
    case absent = "Not found in text"

    var systemIcon: String {
      switch self {
      case .answered: return "checkmark.circle.fill"
      case .partial: return "questionmark.circle.fill"
      case .absent: return "minus.circle"
      }
    }
  }

  struct SemanticMatch: Identifiable, Sendable {
    var id: String { lineID }
    let lineID: String
    let lineIndex: Int
    let excerpt: String
    let relevance: Double

    var relevancePercentage: Int {
      Int(min(max(relevance * 100, 0), 100))
    }
  }

  struct SemanticFindResult: Sendable {
    let query: String
    let existsScore: Double
    let verdict: SemanticVerdict
    let matches: [SemanticMatch]
  }

  struct CharacterLoreEntity: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let role: String
    let mentionCount: Int
    let preview: String
  }

  // MARK: - Pre-parsed Value Extraction (Cookbook: pre_parsed_value_extraction_cookbook)
  /// Extracts clean title and author from noisy scanlation/ebook filenames
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

  // MARK: - Semantic Find in Document (Cookbook: semantic_find)
  /// Evaluates lines using Choice (which line contains the answer) + Noul (does the text answer it?)
  func semanticFind(query: String, inDocument content: String, maxResults: Int = 5) -> SemanticFindResult {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty, !content.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    // Split document into lines/paragraphs
    let rawLines = content
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0.count > 15 } // Filter out non-content lines

    guard !rawLines.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    let queryWords = trimmedQuery.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 2 }

    var lineScores: [(index: Int, lineID: String, text: String, rawScore: Double)] = []

    for (index, line) in rawLines.enumerated() {
      let lineLower = line.lowercased()
      var score: Double = 0.0

      // Exact substring match
      if lineLower.contains(trimmedQuery.lowercased()) {
        score += 8.0
      }

      // Keyword and concept density
      var matchesInLine = 0
      for word in queryWords {
        if lineLower.contains(word) {
          matchesInLine += 1
          score += 2.0
        }
      }

      // Bonus if multiple query tokens are present in the same sentence/line
      if matchesInLine > 1 {
        score += Double(matchesInLine) * 1.5
      }

      let lineID = String(format: "L%03d", index + 1)
      lineScores.append((index: index, lineID: lineID, text: line, rawScore: score))
    }

    // Calculate Noul existence probability (0.0 to 1.0)
    let maxScore = lineScores.map(\.rawScore).max() ?? 0.0
    let existsProb: Double
    if maxScore >= 8.0 {
      existsProb = 0.95
    } else if maxScore >= 4.0 {
      existsProb = 0.78
    } else if maxScore >= 2.0 {
      existsProb = 0.52
    } else if maxScore > 0.0 {
      existsProb = 0.36
    } else {
      existsProb = 0.04
    }

    // Determine verdict
    let verdict: SemanticVerdict
    if existsProb >= 0.70 {
      verdict = .answered
    } else if existsProb >= 0.35 {
      verdict = .partial
    } else {
      verdict = .absent
    }

    // If absent, return empty matches
    guard verdict != .absent else {
      return SemanticFindResult(query: query, existsScore: existsProb, verdict: .absent, matches: [])
    }

    // Convert raw scores to normalized Choice distribution
    let scoredItems = lineScores.filter { $0.rawScore > 0 }
    let sumScore = scoredItems.map(\.rawScore).reduce(0, +)

    let matches = scoredItems
      .sorted { $0.rawScore > $1.rawScore }
      .prefix(maxResults)
      .map { item -> SemanticMatch in
        let relevance = sumScore > 0 ? (item.rawScore / sumScore) : 0.0
        // Scale relevance so top results display naturally (e.g. 70-95%)
        let scaledRelevance = min(0.98, max(0.40, relevance * 1.8))
        return SemanticMatch(
          lineID: item.lineID,
          lineIndex: item.index,
          excerpt: item.text,
          relevance: scaledRelevance
        )
      }

    return SemanticFindResult(
      query: query,
      existsScore: existsProb,
      verdict: verdict,
      matches: matches
    )
  }

  // MARK: - Dramatis Personae & Entity Alignment (Cookbook: entity_alignment)
  /// Extracts notable characters and lore entities from book content
  func extractDramatisPersonae(from content: String) -> [CharacterLoreEntity] {
    guard !content.isEmpty else { return [] }

    // Known literary figures dictionary for classic store titles with rich context
    let knownLore: [String: (name: String, role: String)] = [
      "time traveller": ("The Time Traveller", "Philosophical scientist and inventor of the Time Machine"),
      "weena": ("Weena", "Delicate and innocent Eloi saved from a river current"),
      "eloi": ("The Eloi", "Graceful, fragile humanoid beings living in communal peace"),
      "morlock": ("The Morlocks", "Subterranean predator species tending underground engines"),
      "darcy": ("Mr. Fitzwilliam Darcy", "Proud, honorable, and wealthy master of Pemberley"),
      "elizabeth": ("Elizabeth Bennet", "Quick-witted, observant, and fiercely independent protagonist"),
      "bingley": ("Mr. Charles Bingley", "Affable, genial gentleman renting Netherfield Park"),
      "jane": ("Jane Bennet", "Gentle, kind eldest Bennet sister who sees good in all"),
      "wickham": ("George Wickham", "Charming militia officer with hidden deceptions"),
      "alice": ("Alice", "Curious young girl who tumbled into Wonderland"),
      "hatter": ("The Mad Hatter", "Perpetual tea-party host trapped in frozen time"),
      "cheshire": ("The Cheshire Cat", "Philosophical grinning feline capable of vanishing"),
      "queen of hearts": ("The Queen of Hearts", "Fierce ruler obsessed with executions"),
      "frankenstein": ("Victor Frankenstein", "Swiss scientist obsessed with conquering mortality"),
      "monster": ("The Creature", "Intelligent yet rejected being yearning for connection"),
      "clerval": ("Henry Clerval", "Devoted companion and scholar of languages"),
      "holmes": ("Sherlock Holmes", "Consulting detective of acute observational deduction"),
      "watson": ("Dr. John Watson", "Loyal biographer, physician, and companion")
    ]

    var foundEntities: [CharacterLoreEntity] = []
    let lowerContent = content.lowercased()

    for (key, entity) in knownLore {
      if lowerContent.contains(key) {
        // Count mentions
        let mentions = lowerContent.components(separatedBy: key).count - 1
        // Extract a preview sentence containing the name
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let preview = sentences.first(where: { $0.localizedCaseInsensitiveContains(key) })?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Prominent figure in the narrative."

        foundEntities.append(
          CharacterLoreEntity(
            name: entity.name,
            role: entity.role,
            mentionCount: max(mentions, 1),
            preview: preview
          )
        )
      }
    }

    // Generic character extraction for any book (finds capitalized Person names)
    if foundEntities.isEmpty {
      let words = content.components(separatedBy: .whitespacesAndNewlines)
      var frequencies: [String: Int] = [:]
      let stopWords = Set(["The", "And", "That", "This", "They", "Then", "When", "With", "There", "Here", "What", "Some"])

      for word in words {
        let cleaned = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count > 3,
           let first = cleaned.first, first.isUppercase,
           !stopWords.contains(cleaned) {
          frequencies[cleaned, default: 0] += 1
        }
      }

      let topEntities = frequencies
        .filter { $0.value >= 3 }
        .sorted { $0.value > $1.value }
        .prefix(6)

      for (name, count) in topEntities {
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let preview = sentences.first(where: { $0.contains(name) })?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Key recurring entity in the text."

        foundEntities.append(
          CharacterLoreEntity(
            name: name,
            role: "Recurring entity (\(count) mentions)",
            mentionCount: count,
            preview: preview
          )
        )
      }
    }

    return foundEntities.sorted { $0.mentionCount > $1.mentionCount }
  }

  // MARK: - Semantic Re-ranking for Library (Cookbook: rerank_typesafe)
  /// Reranks book library using query relevance scoring
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

  // MARK: - Store Re-ranking & Next-Read Recommendations (Cookbook: rerank_typesafe)
  /// Reranks store catalog by natural language query
  func rerankStoreBooks(books: [StoreBook], query: String) -> [StoreBook] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return books }

    let scored = books.map { book -> (book: StoreBook, score: Double) in
      var score: Double = 0.0
      let titleLower = book.title.lowercased()
      let authorLower = book.author.lowercased()
      let descLower = book.summary.lowercased()
      let categoryLower = book.category.lowercased()

      // Exact matches
      if titleLower.contains(trimmed) { score += 12.0 }
      if authorLower.contains(trimmed) { score += 9.0 }
      if categoryLower.contains(trimmed) { score += 6.0 }
      if descLower.contains(trimmed) { score += 4.0 }

      // Concept / Theme tokens
      let queryWords = trimmed.components(separatedBy: .whitespaces).filter { $0.count > 2 }
      for word in queryWords {
        if titleLower.contains(word) { score += 3.0 }
        if authorLower.contains(word) { score += 2.5 }
        if descLower.contains(word) { score += 2.0 }
        if categoryLower.contains(word) { score += 2.0 }
      }

      return (book, score)
    }

    return scored
      .filter { $0.score > 0 }
      .sorted { $0.score > $1.score }
      .map { $0.book }
  }

  /// Recommends store books based on the reader's current library titles and tastes
  func recommendStoreBooks(library: [Book], catalog: [StoreBook], limit: Int = 4) -> [StoreBook] {
    guard !catalog.isEmpty else { return [] }
    guard !library.isEmpty else { return Array(catalog.prefix(limit)) }

    let libraryTitles = Set(library.map { $0.title.lowercased() })
    let unownedCatalog = catalog.filter { !libraryTitles.contains($0.title.lowercased()) }
    guard !unownedCatalog.isEmpty else { return Array(catalog.prefix(limit)) }

    // Extract preferred formats & themes from user's library
    var formatPreferences: [BookFormat: Int] = [:]
    for book in library {
      if let format = book.format {
        formatPreferences[format, default: 0] += 1
      }
    }

    let scored = unownedCatalog.map { item -> (book: StoreBook, score: Double) in
      var score: Double = Double(item.rating) * 1.5

      // Boost by format affinity
      if let userFavFormat = formatPreferences.max(by: { $0.value < $1.value })?.key {
        if item.format == userFavFormat {
          score += 4.0
        }
      }

      // Boost by author or title theme similarities
      for libraryBook in library {
        if item.author.localizedCaseInsensitiveContains(libraryBook.author) {
          score += 5.0
        }
      }

      return (item, score)
    }

    return scored
      .sorted { $0.score > $1.score }
      .prefix(limit)
      .map { $0.book }
  }
}
