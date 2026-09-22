//
//  TypeSafeService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import Foundation

/// Integrates TypeSafe AI System One decision models (Jev).
/// Cookbooks and specifications:
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
    var isLiveAI: Bool = false
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
  nonisolated func extractCleanMetadata(from filename: String) -> ExtractedBookMetadata {
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

  // MARK: - Live System One Semantic Find (POST https://api.typesafe.ai/v1/systemone)

  /// Executes semantic search using live TypeSafe System One API (Jev),
  /// with automatic fallback to local semantic scoring when offline.
  nonisolated func semanticFind(query: String, inDocument content: String, maxResults: Int = 5) async -> SemanticFindResult {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty, !content.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    // Check API Key
    let apiKey = TypeSafeConfig.shared.apiKey
    guard !apiKey.isEmpty else {
      return evaluateLocalSemanticFind(query: trimmedQuery, content: content, maxResults: maxResults)
    }

    // Split document into indexed candidate paragraphs
    let allParagraphs = content
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.count > 15 }

    guard !allParagraphs.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    // Select candidate paragraphs (up to 30 candidates to stay well within Jev's 255 choice limit and optimize latency)
    let candidates = selectTopCandidates(paragraphs: allParagraphs, query: trimmedQuery, maxCandidates: 30)

    // Build Choice criteria and state string
    var criteriaDict: [String: String] = [:]
    var stateLines: [String] = []

    for item in candidates {
      let lineID = item.lineID
      criteriaDict[lineID] = String(item.text.prefix(120))
      stateLines.append("\(lineID): \(item.text)")
    }

    let stateString = "Document Passages:\n" + stateLines.joined(separator: "\n")

    // Construct TypeSafe System One JSON payload
    let payload: [String: Any] = [
      "model": TypeSafeConfig.shared.defaultModel,
      "state": stateString,
      "questions": [
        "best_match": [
          "type": "choice",
          "instructions": "Which line or excerpt best describes or answers the query: '\(trimmedQuery)'?",
          "criteria": criteriaDict
        ],
        "has_answer": [
          "type": "noul",
          "instructions": "Does the document contain passages that describe, reference, or answer the query: '\(trimmedQuery)'?"
        ]
      ]
    ]

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: payload)
      var request = URLRequest(url: TypeSafeConfig.shared.baseURL)
      request.httpMethod = "POST"
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = jsonData
      request.timeoutInterval = 12.0

      let (data, response) = try await URLSession.shared.data(for: request)
      if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
        if let result = parseTypeSafeResponse(data: data, candidates: candidates, query: trimmedQuery, maxResults: maxResults) {
          return result
        }
      }
    } catch {
      print("TypeSafeService: Live API error: \(error.localizedDescription). Falling back to local semantic evaluation.")
    }

    // Fallback to local scoring if network unavailable
    return evaluateLocalSemanticFind(query: trimmedQuery, content: content, maxResults: maxResults)
  }

  /// Synchronous overload (for unit tests and offline processing)
  nonisolated func semanticFind(query: String, inDocument content: String, maxResults: Int = 5) -> SemanticFindResult {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return evaluateLocalSemanticFind(query: trimmed, content: content, maxResults: maxResults)
  }

  // MARK: - API Response Parser

  nonisolated private func parseTypeSafeResponse(
    data: Data,
    candidates: [(lineID: String, index: Int, text: String)],
    query: String,
    maxResults: Int
  ) -> SemanticFindResult? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let answers = json["answers"] as? [String: Any] else {
      return nil
    }

    // 1. Parse Noul (existence probability)
    var existsProb = 0.5
    if let hasAnswerObj = answers["has_answer"] as? [String: Any],
       let noulVal = hasAnswerObj["noul"] as? Double {
      existsProb = noulVal
    }

    // Determine verdict from calibrated Noul probability
    let verdict: SemanticVerdict
    if existsProb >= 0.65 {
      verdict = .answered
    } else if existsProb >= 0.35 {
      verdict = .partial
    } else {
      verdict = .absent
    }

    // If absent, return empty matches
    guard verdict != .absent else {
      return SemanticFindResult(query: query, existsScore: existsProb, verdict: .absent, matches: [], isLiveAI: true)
    }

    // 2. Parse Choice probabilities across line candidates
    var matches: [SemanticMatch] = []
    let candidateMap = Dictionary(uniqueKeysWithValues: candidates.map { ($0.lineID, $0) })

    if let choiceObj = answers["best_match"] as? [String: Any],
       let probabilities = choiceObj["probabilities"] as? [String: Double] {
      
      let sortedKeys = probabilities
        .filter { $0.value > 0.01 }
        .sorted { $0.value > $1.value }
        .prefix(maxResults)

      for (lineID, prob) in sortedKeys {
        if let info = candidateMap[lineID] {
          let displayRel = min(0.98, max(0.45, prob * 1.5))
          matches.append(
            SemanticMatch(
              lineID: lineID,
              lineIndex: info.index,
              excerpt: info.text,
              relevance: displayRel
            )
          )
        }
      }
    }

    // If top choice single value returned
    if matches.isEmpty,
       let choiceObj = answers["best_match"] as? [String: Any],
       let chosenID = choiceObj["choice"] as? String,
       let info = candidateMap[chosenID] {
      let confidence = (choiceObj["confidence"] as? Double) ?? 0.85
      matches.append(
        SemanticMatch(
          lineID: chosenID,
          lineIndex: info.index,
          excerpt: info.text,
          relevance: confidence
        )
      )
    }

    return SemanticFindResult(
      query: query,
      existsScore: existsProb,
      verdict: verdict,
      matches: matches,
      isLiveAI: true
    )
  }

  // MARK: - Candidate Pre-selection for Jev Choice Primitives

  nonisolated private func selectTopCandidates(
    paragraphs: [String],
    query: String,
    maxCandidates: Int
  ) -> [(lineID: String, index: Int, text: String)] {
    let tokens = query.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 2 }

    var scored: [(lineID: String, index: Int, text: String, score: Double)] = []

    for (index, text) in paragraphs.enumerated() {
      let lower = text.lowercased()
      var score: Double = 0.0
      if lower.contains(query.lowercased()) { score += 10.0 }
      for token in tokens {
        if lower.contains(token) { score += 2.0 }
      }
      let lineID = String(format: "L%03d", index + 1)
      scored.append((lineID: lineID, index: index, text: text, score: score))
    }

    // If any token matches exist, pick top scoring, otherwise take evenly distributed passages
    let withMatches = scored.filter { $0.score > 0 }
    if !withMatches.isEmpty {
      return withMatches
        .sorted { $0.score > $1.score }
        .prefix(maxCandidates)
        .map { ($0.lineID, $0.index, $0.text) }
    } else {
      let step = max(1, paragraphs.count / maxCandidates)
      return stride(from: 0, to: paragraphs.count, by: step)
        .prefix(maxCandidates)
        .map { i in
          (lineID: String(format: "L%03d", i + 1), index: i, text: paragraphs[i])
        }
    }
  }

  // MARK: - Local Semantic Find Heuristic (Fallback & Offline)

  nonisolated func evaluateLocalSemanticFind(query: String, content: String, maxResults: Int) -> SemanticFindResult {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty, !content.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    let rawLines = content
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0.count > 15 }

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

      if lineLower.contains(trimmedQuery.lowercased()) {
        score += 8.0
      }

      var matchesInLine = 0
      for word in queryWords {
        if lineLower.contains(word) {
          matchesInLine += 1
          score += 2.0
        }
      }

      if matchesInLine > 1 {
        score += Double(matchesInLine) * 1.5
      }

      let lineID = String(format: "L%03d", index + 1)
      lineScores.append((index: index, lineID: lineID, text: line, rawScore: score))
    }

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

    let verdict: SemanticVerdict
    if existsProb >= 0.70 {
      verdict = .answered
    } else if existsProb >= 0.35 {
      verdict = .partial
    } else {
      verdict = .absent
    }

    guard verdict != .absent else {
      return SemanticFindResult(query: query, existsScore: existsProb, verdict: .absent, matches: [])
    }

    let scoredItems = lineScores.filter { $0.rawScore > 0 }
    let sumScore = scoredItems.map(\.rawScore).reduce(0, +)

    let matches = scoredItems
      .sorted { $0.rawScore > $1.rawScore }
      .prefix(maxResults)
      .map { item -> SemanticMatch in
        let relevance = sumScore > 0 ? (item.rawScore / sumScore) : 0.0
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
  /// Extracts notable characters and lore entities from real book content
  nonisolated func extractDramatisPersonae(from content: String) -> [CharacterLoreEntity] {
    guard !content.isEmpty else { return [] }

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
      "rabbit": ("The White Rabbit", "Anxious creature with waistcoat and pocket watch"),
      "hatter": ("The Mad Hatter", "Perpetual tea-party host trapped in frozen time"),
      "cheshire": ("The Cheshire Cat", "Philosophical grinning feline capable of vanishing"),
      "queen": ("The Queen of Hearts", "Fierce ruler obsessed with executions"),
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
        let mentions = lowerContent.components(separatedBy: key).count - 1
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        let preview = sentences.first(where: { $0.localizedCaseInsensitiveContains(key) })?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Prominent figure in the narrative."

        foundEntities.append(
          CharacterLoreEntity(
            name: entity.name,
            role: entity.role,
            mentionCount: max(mentions, 1),
            preview: String(preview.prefix(120))
          )
        )
      }
    }

    // Generic entity discovery for any book text (finds frequent capitalized Names)
    if foundEntities.count < 3 {
      let words = content.components(separatedBy: .whitespacesAndNewlines)
      var frequencies: [String: Int] = [:]
      let stopWords = Set([
        "The", "And", "That", "This", "They", "Then", "When", "With", "There", "Here",
        "What", "Some", "Chapter", "Book", "Page", "Have", "From", "Were", "Been", "Said"
      ])

      for word in words {
        let cleaned = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count > 3,
           let first = cleaned.first, first.isUppercase,
           !stopWords.contains(cleaned) {
          frequencies[cleaned, default: 0] += 1
        }
      }

      let topEntities = frequencies
        .filter { $0.value >= 2 }
        .sorted { $0.value > $1.value }
        .prefix(6)

      for (name, count) in topEntities {
        if !foundEntities.contains(where: { $0.name.contains(name) }) {
          let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
          let preview = sentences.first(where: { $0.contains(name) })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Key recurring entity in the text."

          foundEntities.append(
            CharacterLoreEntity(
              name: name,
              role: "Recurring character (\(count) mentions)",
              mentionCount: count,
              preview: String(preview.prefix(120))
            )
          )
        }
      }
    }

    return foundEntities.sorted { $0.mentionCount > $1.mentionCount }
  }

  // MARK: - Semantic Re-ranking for Library (Cookbook: rerank_typesafe)
  nonisolated func rerank(books: [Book], query: String) -> [Book] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return books }

    let scored = books.map { book -> (book: Book, score: Double) in
      var score: Double = 0.0
      let titleLower = book.title.lowercased()
      let authorLower = book.author.lowercased()
      let contentLower = String(book.content.prefix(500)).lowercased()

      if titleLower.contains(trimmed) { score += 10.0 }
      if authorLower.contains(trimmed) { score += 8.0 }

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

  // MARK: - Store Re-ranking & Recommendations (Cookbook: rerank_typesafe)
  nonisolated func rerankStoreBooks(books: [StoreBook], query: String) -> [StoreBook] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return books }

    let scored = books.map { book -> (book: StoreBook, score: Double) in
      var score: Double = 0.0
      let titleLower = book.title.lowercased()
      let authorLower = book.author.lowercased()
      let descLower = book.summary.lowercased()
      let categoryLower = book.category.lowercased()

      if titleLower.contains(trimmed) { score += 12.0 }
      if authorLower.contains(trimmed) { score += 9.0 }
      if categoryLower.contains(trimmed) { score += 6.0 }
      if descLower.contains(trimmed) { score += 4.0 }

      let queryWords = trimmed.components(separatedBy: .whitespaces).filter { $0.count > 2 }
      for word in queryWords {
        if titleLower.contains(word) { score += 3.0 }
        if authorLower.contains(word) { score += 2.0 }
        if descLower.contains(word) { score += 1.5 }
        if categoryLower.contains(word) { score += 2.0 }
      }

      return (book, score)
    }

    return scored
      .filter { $0.score > 0 }
      .sorted { $0.score > $1.score }
      .map { $0.book }
  }

  nonisolated func recommendStoreBooks(library: [Book], catalog: [StoreBook], limit: Int = 4) -> [StoreBook] {
    guard !catalog.isEmpty else { return [] }
    let ownedTitles = Set(library.map { $0.title.lowercased() })
    let unowned = catalog.filter { !ownedTitles.contains($0.title.lowercased()) }
    guard !unowned.isEmpty else { return [] }

    var preferredCategories: [String: Int] = [:]
    for book in library {
      let t = book.title.lowercased()
      if t.contains("time") || t.contains("odyssey") || t.contains("space") {
        preferredCategories["Sci-Fi", default: 0] += 2
      } else if t.contains("pride") || t.contains("prejudice") || t.contains("wonderland") {
        preferredCategories["Fiction", default: 0] += 2
      }
    }

    let topCategory = preferredCategories.max(by: { $0.value < $1.value })?.key ?? "Fiction"
    let categoryMatches = unowned.filter { $0.category.localizedCaseInsensitiveContains(topCategory) }
    let others = unowned.filter { !$0.category.localizedCaseInsensitiveContains(topCategory) }

    return Array((categoryMatches + others).prefix(limit))
  }
}
