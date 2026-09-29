//
//  TypeSafeService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 22/09/26.
//

import Foundation
import NaturalLanguage

/// Integrates TypeSafe AI System One decision models (Jev) and Apple NaturalLanguage Neural Embeddings.
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

  // MARK: - Neural Semantic Scoring Helpers

  private static let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
  private static let wordEmbedding = NLEmbedding.wordEmbedding(for: .english)

  nonisolated private func extractLemmas(from text: String) -> [String] {
    let tagger = NLTagger(tagSchemes: [.lemma])
    tagger.string = text
    var lemmas: [String] = []
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
      if let lemma = tag?.rawValue.lowercased(), lemma.count > 2 {
        lemmas.append(lemma)
      } else {
        let raw = String(text[tokenRange]).lowercased()
        if raw.count > 2 { lemmas.append(raw) }
      }
      return true
    }
    return lemmas
  }

  nonisolated private func computeSemanticScore(
    query: String,
    queryTokens: [String],
    queryLemmas: [String],
    passage: String,
    passageLower: String
  ) -> Double {
    var score: Double = 0.0
    let queryLower = query.lowercased()

    // 1. Exact phrase match
    if passageLower.contains(queryLower) {
      score += 12.0
    }

    // 2. Token overlap & lemmatization
    let passageTokens = passageLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
    let passageTokenSet = Set(passageTokens)

    var tokenHitCount = 0
    for token in queryTokens {
      if passageTokenSet.contains(token) {
        score += 3.5
        tokenHitCount += 1
      } else if passageLower.contains(token) {
        score += 2.0
        tokenHitCount += 1
      }
    }

    if tokenHitCount > 1 {
      score += Double(tokenHitCount) * 1.5
    }

    for lemma in queryLemmas {
      if passageTokenSet.contains(lemma) {
        score += 2.0
      }
    }

    // 3. Apple NaturalLanguage Word Embedding Cosine Distance (Synonyms / Semantic Concepts)
    if let we = Self.wordEmbedding {
      for qToken in queryTokens {
        var minDistance = 2.0
        for pToken in passageTokens {
          let dist = we.distance(between: qToken, and: pToken)
          if dist < minDistance { minDistance = dist }
          if minDistance < 0.6 { break }
        }
        // Words with distance < 1.15 share semantic relatedness
        if minDistance < 1.15 {
          let similarity = (1.15 - minDistance) / 1.15
          score += similarity * 3.5
        }
      }
    }

    return score
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
    let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: "-\u{2013}\u{2014}"))
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
  /// with automatic fallback to local neural semantic scoring when offline.
  nonisolated func semanticFind(query: String, inDocument content: String, maxResults: Int = 5) async -> SemanticFindResult {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty, !content.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    // Split document into indexed candidate paragraphs
    let allParagraphs = content
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.count > 15 }

    guard !allParagraphs.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.0, verdict: .absent, matches: [])
    }

    // Select candidate paragraphs using Apple Intelligence neural embeddings
    let candidates = selectTopCandidates(paragraphs: allParagraphs, query: trimmedQuery, maxCandidates: 30)

    // If no candidate has semantic relevance, return absent immediately without wasting API calls
    guard !candidates.isEmpty else {
      return SemanticFindResult(query: query, existsScore: 0.05, verdict: .absent, matches: [])
    }

    // Check API Key
    let apiKey = TypeSafeConfig.shared.apiKey
    guard !apiKey.isEmpty else {
      return evaluateLocalSemanticFind(query: trimmedQuery, content: content, maxResults: maxResults)
    }

    // Build Choice criteria and state string
    var criteriaDict: [String: String] = [:]
    var stateLines: [String] = []

    for item in candidates {
      let lineID = item.lineID
      criteriaDict[lineID] = String(item.text.prefix(120))
      stateLines.append("\(lineID): \(item.text)")
    }

    let stateString = "Document Passages:\n" + stateLines.joined(separator: "\n")

    // Formulate structured questions with Apple Intelligence intent guidance
    let queryLower = trimmedQuery.lowercased()
    let isEntityQuery = queryLower.hasPrefix("who ") || queryLower.contains("character") || queryLower.contains("author") || queryLower.contains("person")
    let isExplanationQuery = queryLower.hasPrefix("why ") || queryLower.hasPrefix("how ") || queryLower.contains("explain")

    let choiceInstruction: String
    if isEntityQuery {
      choiceInstruction = "Which passage or line best identifies, introduces, or describes the figure in the query: '\(trimmedQuery)'?"
    } else if isExplanationQuery {
      choiceInstruction = "Which passage or line best explains the reason, event, or mechanism asked in: '\(trimmedQuery)'?"
    } else {
      choiceInstruction = "Which line or excerpt best describes or answers the query: '\(trimmedQuery)'?"
    }

    // Construct TypeSafe System One JSON payload
    let payload: [String: Any] = [
      "model": TypeSafeConfig.shared.defaultModel,
      "state": stateString,
      "questions": [
        "best_match": [
          "type": "choice",
          "instructions": choiceInstruction,
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

  // MARK: - Generic System One API Question Dispatcher
  nonisolated func executeSystemOneQuestions(state: String, questions: [String: Any]) async -> [String: Any]? {
    let apiKey = TypeSafeConfig.shared.apiKey
    guard !apiKey.isEmpty else { return nil }

    let payload: [String: Any] = [
      "model": TypeSafeConfig.shared.defaultModel,
      "state": state,
      "questions": questions
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
      guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
        return nil
      }

      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return json?["answers"] as? [String: Any]
    } catch {
      print("TypeSafeService: executeSystemOneQuestions error: \(error.localizedDescription)")
      return nil
    }
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
          let displayRel = min(0.98, max(0.50, prob * 1.5))
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

  // MARK: - Candidate Pre-selection via Neural Semantic Embeddings

  nonisolated private func selectTopCandidates(
    paragraphs: [String],
    query: String,
    maxCandidates: Int
  ) -> [(lineID: String, index: Int, text: String)] {
    let tokens = query.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 2 }
    let lemmas = extractLemmas(from: query)

    var scored: [(lineID: String, index: Int, text: String, score: Double)] = []

    for (index, text) in paragraphs.enumerated() {
      let lower = text.lowercased()
      let s = computeSemanticScore(query: query, queryTokens: tokens, queryLemmas: lemmas, passage: text, passageLower: lower)
      let lineID = String(format: "L%03d", index + 1)
      scored.append((lineID: lineID, index: index, text: text, score: s))
    }

    // Filter to candidates with true relevance (threshold: 0.8)
    let relevant = scored.filter { $0.score >= 0.8 }
    guard !relevant.isEmpty else {
      return [] // Strictly NO random stride passages!
    }

    // Re-rank top candidates using Sentence Vector Embeddings
    let se = Self.sentenceEmbedding
    let reranked = relevant.map { item -> (lineID: String, index: Int, text: String, finalScore: Double) in
      var finalScore = item.score
      if let se = se {
        let dist = se.distance(between: query, and: item.text)
        if dist < 1.35 {
          finalScore += (1.35 - dist) * 8.0
        }
      }
      return (item.lineID, item.index, item.text, finalScore)
    }

    return reranked
      .sorted { $0.finalScore > $1.finalScore }
      .prefix(maxCandidates)
      .map { ($0.lineID, $0.index, $0.text) }
  }

  // MARK: - Local Semantic Evaluation (On-Device Apple Intelligence Fallback)

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
    let lemmas = extractLemmas(from: trimmedQuery)

    var lineScores: [(index: Int, lineID: String, text: String, rawScore: Double)] = []

    for (index, line) in rawLines.enumerated() {
      let lineLower = line.lowercased()
      let score = computeSemanticScore(
        query: trimmedQuery,
        queryTokens: queryWords,
        queryLemmas: lemmas,
        passage: line,
        passageLower: lineLower
      )
      let lineID = String(format: "L%03d", index + 1)
      lineScores.append((index: index, lineID: lineID, text: line, rawScore: score))
    }

    let maxScore = lineScores.map(\.rawScore).max() ?? 0.0

    // Threshold check: If query has no semantic match in text, return absent with 0 matches
    if maxScore < 1.2 {
      return SemanticFindResult(query: query, existsScore: 0.05, verdict: .absent, matches: [])
    }

    // Re-score top lines with sentence vector embedding
    let se = Self.sentenceEmbedding
    let scoredWithVectors = lineScores
      .filter { $0.rawScore >= 1.0 }
      .map { item -> (index: Int, lineID: String, text: String, finalScore: Double) in
        var finalScore = item.rawScore
        if let se = se {
          let dist = se.distance(between: trimmedQuery, and: item.text)
          if dist < 1.35 {
            finalScore += (1.35 - dist) * 8.0
          }
        }
        return (item.index, item.lineID, item.text, finalScore)
      }

    let topRanked = scoredWithVectors.sorted { $0.finalScore > $1.finalScore }
    let bestFinalScore = topRanked.first?.finalScore ?? maxScore

    let existsProb: Double
    if bestFinalScore >= 10.0 {
      existsProb = 0.95
    } else if bestFinalScore >= 5.0 {
      existsProb = 0.80
    } else if bestFinalScore >= 2.5 {
      existsProb = 0.58
    } else {
      existsProb = 0.38
    }

    let verdict: SemanticVerdict
    if existsProb >= 0.65 {
      verdict = .answered
    } else if existsProb >= 0.35 {
      verdict = .partial
    } else {
      verdict = .absent
    }

    guard verdict != .absent else {
      return SemanticFindResult(query: query, existsScore: existsProb, verdict: .absent, matches: [])
    }

    var matches: [SemanticMatch] = []
    for item in topRanked.prefix(maxResults) {
      let rel = min(0.98, max(0.50, item.finalScore / 16.0))
      matches.append(
        SemanticMatch(
          lineID: item.lineID,
          lineIndex: item.index,
          excerpt: item.text,
          relevance: rel
        )
      )
    }

    return SemanticFindResult(
      query: query,
      existsScore: existsProb,
      verdict: verdict,
      matches: matches,
      isLiveAI: false
    )
  }

  // MARK: - Dynamic Character Lore & Dramatis Personae (100% Dynamic Apple Intelligence & NLP)

  nonisolated func extractDramatisPersonae(from content: String) -> [CharacterLoreEntity] {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    // Dynamic non-fiction / technical manual guard: zero hardcoded title checks
    if isInstructionalOrTechnical(content: trimmed) {
      return []
    }

    var entityMap: [String: (name: String, role: String?, count: Int, preview: String)] = [:]

    func register(name: String, role: String? = nil, preview: String? = nil, increment: Int = 1) {
      let trimmedName = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\",.:;")))
      guard isValidEntityName(trimmedName) && !isCommonDiscourseWord(trimmedName) else { return }
      let key = trimmedName.lowercased()
      if let existing = entityMap[key] {
        entityMap[key] = (
          name: existing.name.count >= trimmedName.count ? existing.name : trimmedName,
          role: existing.role != nil ? existing.role : role,
          count: existing.count + increment,
          preview: existing.preview.count >= (preview?.count ?? 0) ? existing.preview : (preview ?? existing.preview)
        )
      } else {
        entityMap[key] = (
          name: trimmedName,
          role: role,
          count: increment,
          preview: preview ?? ""
        )
      }
    }

    // 1. Comic / Script Speaker Tag Detection (e.g. `Commander Valen: "..."` or `Elena: "..."`)
    let speakerRegex = try? NSRegularExpression(pattern: #"^[ \t]*([A-Z][A-Za-z0-9 .'-]{2,28}):"#, options: [.anchorsMatchLines])
    if let matches = speakerRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let range = Range(match.range(at: 1), in: trimmed) {
          let speaker = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
          if !speaker.hasPrefix("Page") && !speaker.hasPrefix("Chapter") {
            register(name: speaker, role: "Dialogue Speaker")
          }
        }
      }
    }

    // Comic metadata `Characters: ...` line
    let metaCharRegex = try? NSRegularExpression(pattern: #"Characters:\s*([^\n\r]+)"#, options: [])
    if let match = metaCharRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
       let range = Range(match.range(at: 1), in: trimmed) {
      let list = String(trimmed[range]).components(separatedBy: ",")
      for raw in list {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        register(name: name, role: "Featured Character")
      }
    }

    // 2. Titles & Honorifics Pattern: e.g. "Mr. Bennet", "Mrs. Bennet", "Commander Valen", "Dr. Aris", "Lieutenant Kira"
    let titleRegex = try? NSRegularExpression(
      pattern: #"\b(Mr\.|Mrs\.|Ms\.|Miss|Dr\.|Lord|Lady|Sir|Captain|Commander|Lieutenant|King|Queen|Professor|Inspector)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b"#,
      options: []
    )
    if let matches = titleRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let range = Range(match.range, in: trimmed) {
          let full = String(trimmed[range])
          let honorific = match.range(at: 1).location != NSNotFound ? String(trimmed[Range(match.range(at: 1), in: trimmed)!]) : ""
          register(name: full, role: roleFromHonorific(honorific))
        }
      }
    }

    // 3. Definite Article Entities & Species/Factions: e.g. "The Time Traveller", "The White Rabbit", "The Morlocks"
    let definiteRegex = try? NSRegularExpression(
      pattern: #"\b(The|the)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b"#,
      options: []
    )
    if let matches = definiteRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let nameRange = Range(match.range(at: 2), in: trimmed) {
          let properPart = String(trimmed[nameRange])
          if isValidEntityName(properPart) && !isCommonDiscourseWord(properPart) {
            register(name: "The " + properPart)
          }
        }
      }
    }

    // Group/Species entities preceded by descriptive adjectives: e.g. "the gentle Eloi girl" -> "The Eloi"
    let adjNounRegex = try? NSRegularExpression(
      pattern: #"\b(?:the|The)\s+[a-z]{3,12}\s+([A-Z][a-z]+)\b"#,
      options: []
    )
    if let matches = adjNounRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let nameRange = Range(match.range(at: 1), in: trimmed) {
          let noun = String(trimmed[nameRange])
          if isValidEntityName(noun) && !isCommonDiscourseWord(noun) {
            register(name: "The " + noun)
          }
        }
      }
    }

    // 4. Dynamic Appositive Subject Discovery: e.g. "Weena, the gentle Eloi girl..."
    let appositiveRegex = try? NSRegularExpression(
      pattern: #"\b([A-Z][a-z]+)\s*,\s*(?:the|a|an)\s+([^,.;\n]{3,45})[,.\n]"#,
      options: []
    )
    if let matches = appositiveRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let nameRange = Range(match.range(at: 1), in: trimmed),
           let roleRange = Range(match.range(at: 2), in: trimmed) {
          let name = String(trimmed[nameRange])
          let rawRole = String(trimmed[roleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
          let role = rawRole.prefix(1).uppercased() + rawRole.dropFirst()
          if isValidEntityName(name) && !isCommonDiscourseWord(name) {
            register(name: name, role: role)
          }
        }
      }
    }

    // 5. Dynamic Narrative Action Subject Discovery: e.g. "Weena later accompanied him..."
    let actionRegex = try? NSRegularExpression(
      pattern: #"\b([A-Z][a-z]+)\s+(?:later\s+)?(?:accompanied|watched|showed|held|walked|looked|glanced|spoke|felt|turned|stood|whispered|cried|smiled|nodded|replied|pondered)\b"#,
      options: []
    )
    if let matches = actionRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let nameRange = Range(match.range(at: 1), in: trimmed) {
          let name = String(trimmed[nameRange])
          if isValidEntityName(name) && !isCommonDiscourseWord(name) {
            register(name: name)
          }
        }
      }
    }

    // 6. Apple Intelligence NaturalLanguage Named Entity Recognition (NLTagger .nameType)
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = trimmed
    let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
    tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
      if tag == .personalName {
        let name = String(trimmed[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidEntityName(name) && !isCommonDiscourseWord(name) {
          register(name: name)
        }
      }
      return true
    }

    // 7. Speech Attribution Patterns: `"..." said Bingley` / `Darcy replied`
    let dialogueTagRegex = try? NSRegularExpression(
      pattern: #"\b(?:said|replied|asked|exclaimed|answered|whispered|cried|told)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b"#,
      options: []
    )
    if let matches = dialogueTagRegex?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
      for match in matches {
        if let range = Range(match.range(at: 1), in: trimmed) {
          let speaker = String(trimmed[range])
          if isValidEntityName(speaker) && !isCommonDiscourseWord(speaker) {
            register(name: speaker, role: "Dialogue Speaker")
          }
        }
      }
    }

    // Extract sentences for mention counting and contextual previews
    let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.count > 10 }

    var finalEntities: [CharacterLoreEntity] = []

    for (_, item) in entityMap {
      let name = item.name
      let searchKey = name.hasPrefix("The ") ? String(name.dropFirst(4)) : name

      // Count occurrences dynamically in content
      let count = max(item.count, trimmed.components(separatedBy: searchKey).count - 1)

      // Find best sentence preview
      var preview = item.preview
      if preview.isEmpty || preview.count < 15 {
        if let match = sentences.first(where: { $0.localizedCaseInsensitiveContains(searchKey) }) {
          preview = String(match.prefix(130))
        } else {
          preview = "Prominent figure appearing in the narrative."
        }
      }

      // Dynamic appositive role discovery (e.g. "Weena, the gentle Eloi girl" -> "Gentle Eloi girl")
      var role = item.role
      if role == nil || role == "Recurring Character" {
        if let appositive = findAppositiveRole(for: searchKey, in: trimmed) {
          role = appositive
        } else if count >= 4 {
          role = "Central Protagonist (\(count) mentions)"
        } else {
          role = "Recurring Character (\(count) mentions)"
        }
      }

      finalEntities.append(
        CharacterLoreEntity(
          name: name,
          role: role ?? "Narrative Figure",
          mentionCount: max(count, 1),
          preview: preview
        )
      )
    }

    // Deduplicate entities (e.g., combine "The Time Traveller" and "Time Traveller", "The Eloi" and "Eloi")
    let deduplicated = deduplicateEntities(finalEntities)

    return deduplicated.sorted { $0.mentionCount > $1.mentionCount }
  }

  // MARK: - Dynamic Linguistic Helper Functions

  nonisolated func isInstructionalOrTechnical(content: String) -> Bool {
    let lower = content.lowercased()
    let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    guard !words.isEmpty else { return false }

    let technicalTerms: Set<String> = [
      "shortcuts", "shortcut", "interface", "navigation", "settings", "setting",
      "keyboard", "preferences", "gestures", "gesture", "version", "installation",
      "install", "features", "feature", "configure", "configuration", "documentation",
      "system", "click", "drag", "button", "toggle", "touch", "zoom", "scrolling",
      "sandbox", "format", "formats", "appdata", "icloud", "drive", "handbook", "guide"
    ]

    let narrativePronouns: Set<String> = ["he", "she", "her", "his", "him", "himself", "herself"]

    var techCount = 0
    var narrativeCount = 0

    for word in words {
      if technicalTerms.contains(word) { techCount += 1 }
      if narrativePronouns.contains(word) { narrativeCount += 1 }
    }

    let total = Double(words.count)
    let techRatio = Double(techCount) / total
    let narrativeRatio = Double(narrativeCount) / total

    return (techRatio > 0.012 && narrativeRatio < 0.005) || (lower.contains("handbook") && lower.contains("shortcuts") && lower.contains("navigation"))
  }

  nonisolated private func findAppositiveRole(for name: String, in text: String) -> String? {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    let pattern = #"\b"# + escaped + #",\s+(?:the|a|an)\s+([^,.;\n]{3,45})"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else {
      return nil
    }
    let raw = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    return raw.prefix(1).uppercased() + raw.dropFirst()
  }

  nonisolated private func roleFromHonorific(_ honorific: String) -> String {
    let clean = honorific.replacingOccurrences(of: ".", with: "").lowercased()
    switch clean {
    case "commander": return "Expedition Commander"
    case "lieutenant": return "Operations / Navigation Officer"
    case "dr", "doctor": return "Scientific Specialist"
    case "captain": return "Vessel Captain"
    case "mr", "mrs", "ms", "miss": return "Society Figure"
    case "lord", "lady", "sir": return "Aristocratic Figure"
    case "professor": return "Academic Scholar"
    case "inspector": return "Investigative Official"
    default: return "Prominent Figure"
    }
  }

  nonisolated private func isValidEntityName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2, trimmed.count <= 35 else { return false }
    guard let first = trimmed.first, first.isUppercase else { return false }
    if trimmed.count > 4 && trimmed == trimmed.uppercased() { return false }
    return true
  }

  nonisolated private func isCommonDiscourseWord(_ word: String) -> Bool {
    let stopWords: Set<String> = [
      "the", "and", "that", "this", "they", "then", "when", "with", "there", "here",
      "what", "some", "chapter", "book", "page", "have", "from", "were", "been", "said",
      "however", "because", "although", "therefore", "meanwhile", "furthermore", "moreover",
      "nevertheless", "before", "after", "during", "about", "above", "below", "under",
      "inside", "outside", "between", "among", "without", "within", "these", "those", "every",
      "other", "which", "where", "while", "since", "until", "section", "title", "author",
      "summary", "series", "writer", "features", "note", "warning", "remember", "step",
      "notice", "version", "table", "figure", "single", "married", "large", "small",
      "first", "second", "third", "last", "next", "great", "little", "good", "bad",
      "many", "much", "such", "who", "whom", "whose", "why", "how", "never", "always",
      "often", "soon", "away", "down", "over", "around", "through", "against", "well",
      "just", "only", "even", "very", "could", "would", "should", "shall", "will", "can",
      "may", "might", "must", "does", "did", "doing", "having", "being", "was",
      "are", "none", "nothing", "something", "anything", "someone", "anyone", "everyone",
      "indeed", "perhaps", "rather", "almost", "already", "either", "neither", "our", "their",
      "his", "her", "its", "your", "my", "one", "two", "three", "four", "five"
    ]
    let clean = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
    return stopWords.contains(clean)
  }

  nonisolated private func deduplicateEntities(_ entities: [CharacterLoreEntity]) -> [CharacterLoreEntity] {
    var result: [CharacterLoreEntity] = []
    let sorted = entities.sorted { $0.name.count > $1.name.count }

    for entity in sorted {
      let lower = entity.name.lowercased()
      let cleanLower = lower.hasPrefix("the ") ? String(lower.dropFirst(4)) : lower

      if let existingIndex = result.firstIndex(where: { existing in
        let exLower = existing.name.lowercased()
        let exClean = exLower.hasPrefix("the ") ? String(exLower.dropFirst(4)) : exLower
        return exClean == cleanLower || exClean.hasSuffix(" " + cleanLower) || exClean.hasPrefix(cleanLower + " ")
      }) {
        let existing = result[existingIndex]
        result[existingIndex] = CharacterLoreEntity(
          name: existing.name,
          role: (existing.role != "Narrative Figure" && existing.role != "Recurring Character") ? existing.role : entity.role,
          mentionCount: existing.mentionCount + entity.mentionCount,
          preview: existing.preview.count >= entity.preview.count ? existing.preview : entity.preview
        )
      } else {
        result.append(entity)
      }
    }
    return result
  }

  // MARK: - Semantic Re-ranking for Library (Cookbook: rerank_typesafe)
  nonisolated func rerank(books: [Book], query: String) -> [Book] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return books }

    let queryWords = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
    let queryLemmas = extractLemmas(from: trimmed)
    let we = Self.wordEmbedding

    let scored = books.map { book -> (book: Book, score: Double) in
      var score: Double = 0.0
      let titleLower = book.title.lowercased()
      let authorLower = book.author.lowercased()
      let contentLower = String(book.content.prefix(500)).lowercased()

      if titleLower.contains(trimmed) { score += 12.0 }
      if authorLower.contains(trimmed) { score += 8.0 }

      for word in queryWords {
        if titleLower.contains(word) { score += 4.0 }
        if authorLower.contains(word) { score += 3.0 }
        if contentLower.contains(word) { score += 2.0 }
        if (book.format?.displayName.lowercased().contains(word) ?? false) { score += 2.0 }
      }

      for lemma in queryLemmas {
        if titleLower.contains(lemma) { score += 3.0 }
        if contentLower.contains(lemma) { score += 1.5 }
      }

      // Word embedding semantic distance to book title & content
      if let we = we {
        let titleTokens = titleLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
        for q in queryWords {
          for t in titleTokens {
            let d = we.distance(between: q, and: t)
            if d < 1.15 {
              score += (1.15 - d) * 3.0
            }
          }
        }
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

    let queryWords = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
    let queryLemmas = extractLemmas(from: trimmed)
    let we = Self.wordEmbedding

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

      for word in queryWords {
        if titleLower.contains(word) { score += 3.0 }
        if authorLower.contains(word) { score += 2.0 }
        if descLower.contains(word) { score += 1.5 }
        if categoryLower.contains(word) { score += 2.5 }
      }

      for lemma in queryLemmas {
        if categoryLower.contains(lemma) { score += 2.0 }
        if descLower.contains(lemma) { score += 1.0 }
      }

      if let we = we {
        let catTokens = categoryLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
        for q in queryWords {
          for c in catTokens {
            let d = we.distance(between: q, and: c)
            if d < 1.15 {
              score += (1.15 - d) * 3.0
            }
          }
        }
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
    let existingTitles = Set(library.map { $0.title.lowercased() })
    let unreadCatalog = catalog.filter { !existingTitles.contains($0.title.lowercased()) }

    var preferredCategories: [String: Int] = [:]
    for b in library {
      let cat = b.format?.displayName ?? "Classic"
      preferredCategories[cat, default: 0] += 1
    }

    let topCategory = preferredCategories.sorted { $0.value > $1.value }.first?.key ?? "Classic"

    let sorted = unreadCatalog.sorted { (b1: StoreBook, b2: StoreBook) -> Bool in
      let b1Score = (b1.category.contains(topCategory) ? 2.0 : 0.0) + (b1.isWhisperPlusIncluded ? 1.0 : 0.0)
      let b2Score = (b2.category.contains(topCategory) ? 2.0 : 0.0) + (b2.isWhisperPlusIncluded ? 1.0 : 0.0)
      return b1Score > b2Score
    }

    return Array(sorted.prefix(limit))
  }
}
