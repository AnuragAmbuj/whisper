//
//  AISummarizerService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 24/09/26.
//

import Foundation
import NaturalLanguage

/// On-Device Apple Intelligence Summarizer & Literary Analysis Service.
/// Uses Apple's NaturalLanguage framework and neural linguistic heuristics
/// to synthesize chapter summaries, themes, reading mood, and key takeaways across
/// Novels, EPUBs, PDFs, and CBZ/CBR Comics.
final class AISummarizerService: @unchecked Sendable {
    static let shared = AISummarizerService()
    private init() {}
    
    struct AIReadingInsights: Sendable {
        let title: String
        let chapterOrSection: String
        let executiveSummary: String
        let keyTakeaways: [String]
        let toneAndMood: String
        let moodIcon: String
        let estimatedReadMinutes: Int
        let wordCount: Int
        let characters: [TypeSafeService.CharacterLoreEntity]
    }
    
    /// Analyzes text content and generates on-device literary insights
    func generateInsights(for text: String, bookTitle: String, sectionName: String = "Current Section") async -> AIReadingInsights {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AIReadingInsights(
                title: bookTitle,
                chapterOrSection: sectionName,
                executiveSummary: "No text available to analyze.",
                keyTakeaways: [],
                toneAndMood: "Neutral",
                moodIcon: "book",
                estimatedReadMinutes: 0,
                wordCount: 0,
                characters: []
            )
        }
        
        let words = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count
        let readMinutes = max(1, Int(ceil(Double(wordCount) / 225.0)))
        
        // 1. Generate Executive Summary
        let summary = extractKeySummary(from: trimmed, bookTitle: bookTitle, maxSentences: 3)
        
        // 2. Extract Key Takeaways
        let takeaways = extractKeyTakeaways(from: trimmed, count: 4)
        
        // 3. Detect Tone and Mood
        let (mood, icon) = analyzeToneAndMood(from: trimmed)
        
        // 4. Extract Characters and Lore
        let characters = extractCharacters(from: trimmed)
        
        return AIReadingInsights(
            title: bookTitle,
            chapterOrSection: sectionName,
            executiveSummary: summary,
            keyTakeaways: takeaways,
            toneAndMood: mood,
            moodIcon: icon,
            estimatedReadMinutes: readMinutes,
            wordCount: wordCount,
            characters: characters
        )
    }
    
    // MARK: - Sentence Extraction & Summarization
    
    private func extractKeySummary(from text: String, bookTitle: String, maxSentences: Int) -> String {
        // Comic / Graphic novel handling with Metadata or Page dialogue
        if text.contains("[Metadata]") || text.contains("[Page ") {
            var summaryLines: [String] = []
            
            // If ComicInfo summary is present
            if let summaryRange = text.range(of: "Summary: ") {
                let rest = text[summaryRange.upperBound...]
                let line = rest.components(separatedBy: .newlines).first ?? ""
                if !line.isEmpty {
                    summaryLines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            
            // Extract key dialogue moments across pages
            let pages = text.components(separatedBy: "[Page ")
            for page in pages.dropFirst().prefix(3) {
                let lines = page.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.contains(":") && !$0.hasPrefix("Chapter") }
                if let firstLine = lines.first {
                    summaryLines.append(firstLine)
                }
            }
            
            if !summaryLines.isEmpty {
                return summaryLines.joined(separator: " ")
            }
        }
        
        let sentences = parseSentences(from: text)
        guard sentences.count > maxSentences else {
            return sentences.isEmpty ? "Reading overview for \(bookTitle)." : sentences.joined(separator: " ")
        }
        
        // Score sentences by word frequency and positional prominence
        let wordFrequencies = computeWordFrequencies(from: text)
        var scored: [(sentence: String, index: Int, score: Double)] = []
        
        for (i, sentence) in sentences.enumerated() {
            let sentenceWords = sentence.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
            guard !sentenceWords.isEmpty else { continue }
            
            var score = 0.0
            for w in sentenceWords {
                score += wordFrequencies[w] ?? 0.0
            }
            score /= Double(sentenceWords.count)
            
            // Bias towards opening and closing thematic statements
            if i == 0 || i == 1 { score *= 1.4 }
            if i == sentences.count - 1 { score *= 1.25 }
            
            scored.append((sentence: sentence, index: i, score: score))
        }
        
        let topSentences = scored
            .sorted { $0.score > $1.score }
            .prefix(maxSentences)
            .sorted { $0.index < $1.index }
            .map { $0.sentence }
            
        return topSentences.joined(separator: " ")
    }
    
    // MARK: - Key Takeaways Extraction
    
    private func extractKeyTakeaways(from text: String, count: Int) -> [String] {
        // Comic dialogue and scene extraction
        if text.contains("[Page ") {
            var takeaways: [String] = []
            let pages = text.components(separatedBy: "[Page ")
            for (index, page) in pages.dropFirst().enumerated() {
                let lines = page.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 20 && !$0.hasPrefix("Chapter") && !$0.hasPrefix("THE COSMIC") }
                
                if let bestLine = lines.first {
                    takeaways.append("Page \(index + 1): \(bestLine)")
                }
                if takeaways.count >= count { break }
            }
            if !takeaways.isEmpty {
                return takeaways
            }
        }
        
        let sentences = parseSentences(from: text)
        guard !sentences.isEmpty else { return [] }
        
        var informativeCandidates = sentences.filter { s in
            let length = s.count
            return length >= 35 && length <= 240 && !s.contains("?")
        }
        
        if informativeCandidates.count < count {
            informativeCandidates = sentences.filter { $0.count >= 25 }
        }
        
        let selected: [String]
        if informativeCandidates.count <= count {
            selected = informativeCandidates
        } else {
            let step = max(1, informativeCandidates.count / count)
            selected = stride(from: 0, to: informativeCandidates.count, by: step)
                .prefix(count)
                .map { informativeCandidates[$0] }
        }
        
        return selected.map { s in
            var cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") {
                cleaned += "."
            }
            return cleaned
        }
    }
    
    // MARK: - Tone & Mood Analysis
    
    private func analyzeToneAndMood(from text: String) -> (mood: String, icon: String) {
        let lower = text.lowercased()
        
        let philosophicalTerms = ["truth", "reason", "nature", "mind", "soul", "knowledge", "existence", "thought", "wisdom", "morals"]
        let suspenseTerms = ["danger", "fear", "shadow", "dark", "secret", "creature", "blood", "whisper", "night", "dread", "terror", "warning", "anomaly"]
        let romanticTerms = ["love", "heart", "affection", "marriage", "delight", "fond", "passion", "gentle", "beauty", "tender", "wife", "single"]
        let whimsicalTerms = ["curious", "wonder", "rabbit", "tea", "strange", "laugh", "dream", "magic", "funny", "peculiar", "daisy"]
        let adventureTerms = ["journey", "travel", "discover", "machine", "future", "island", "explore", "ship", "sea", "path", "starship", "nebula", "beacon"]
        
        func countMatches(_ terms: [String]) -> Int {
            terms.reduce(0) { count, term in
                count + (lower.contains(term) ? 1 : 0)
            }
        }
        
        let philScore = countMatches(philosophicalTerms)
        let suspScore = countMatches(suspenseTerms)
        let romScore = countMatches(romanticTerms)
        let whimScore = countMatches(whimsicalTerms)
        let advScore = countMatches(adventureTerms)
        
        let maxScore = max(philScore, suspScore, romScore, whimScore, advScore)
        guard maxScore > 0 else {
            return ("Contemplative & Narrative", "sparkles")
        }
        
        if maxScore == advScore {
            return ("Adventurous & Energetic", "safari.fill")
        } else if maxScore == suspScore {
            return ("Mysterious & Tense", "moon.stars.fill")
        } else if maxScore == philScore {
            return ("Philosophical & Reflective", "brain.head.profile")
        } else if maxScore == romScore {
            return ("Romantic & Lyrical", "heart.fill")
        } else {
            return ("Whimsical & Imaginative", "wand.and.stars")
        }
    }
    
    // MARK: - Character Lore Extraction
    
    private func extractCharacters(from text: String) -> [TypeSafeService.CharacterLoreEntity] {
        var entities: [TypeSafeService.CharacterLoreEntity] = []
        var seenNames = Set<String>()
        
        // 1. Comic characters from ComicInfo.xml header or dialogue speaker tags
        if text.contains("Characters: ") {
            if let range = text.range(of: "Characters: ") {
                let rest = text[range.upperBound...]
                let line = rest.components(separatedBy: .newlines).first ?? ""
                let charNames = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                for name in charNames {
                    if !seenNames.contains(name.lowercased()) {
                        seenNames.insert(name.lowercased())
                        entities.append(TypeSafeService.CharacterLoreEntity(
                            name: name,
                            role: "Comic Character",
                            mentionCount: 3,
                            preview: "Featured prominently in the comic script and dialogue."
                        ))
                    }
                }
            }
        }
        
        // Check for dialogue speakers formatted like "Commander Valen:", "Lieutenant Kira:"
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if let colonIdx = line.firstIndex(of: ":") {
                let speaker = String(line[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                if speaker.count > 2 && speaker.count < 30 && !speaker.contains("[") && !speaker.hasPrefix("Chapter") && !speaker.hasPrefix("Page") && !speaker.hasPrefix("Title") && !speaker.hasPrefix("Summary") && !speaker.hasPrefix("Series") && !speaker.hasPrefix("Writer") {
                    let lower = speaker.lowercased()
                    if !seenNames.contains(lower) {
                        seenNames.insert(lower)
                        entities.append(TypeSafeService.CharacterLoreEntity(
                            name: speaker,
                            role: "Active Speaker / Protagonist",
                            mentionCount: 2,
                            preview: "Character delivering dialogue in this section."
                        ))
                    }
                }
            }
        }
        
        // 2. Known classical literature lore from TypeSafeService
        let known = TypeSafeService.shared.extractDramatisPersonae(from: text)
        for entity in known {
            if !seenNames.contains(entity.name.lowercased()) {
                seenNames.insert(entity.name.lowercased())
                entities.append(entity)
            }
        }
        
        // 3. Dynamic Named Entity Recognition using Apple NaturalLanguage
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        var personCounts: [String: Int] = [:]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName {
                let name = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count > 2 && !name.contains("\n") {
                    personCounts[name, default: 0] += 1
                }
            }
            return true
        }
        
        for (name, count) in personCounts.sorted(by: { $0.value > $1.value }) {
            let lower = name.lowercased()
            if !seenNames.contains(lower) && count >= 2 {
                seenNames.insert(lower)
                entities.append(TypeSafeService.CharacterLoreEntity(
                    name: name,
                    role: "Prominent Character (\(count) mentions)",
                    mentionCount: count,
                    preview: "Frequently featured in the text narrative."
                ))
            }
        }
        
        return Array(entities.prefix(6))
    }
    
    // MARK: - Helpers
    
    private func parseSentences(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count > 15 {
                sentences.append(s)
            }
            return true
        }
        return sentences
    }
    
    private func computeWordFrequencies(from text: String) -> [String: Double] {
        let stopWords: Set<String> = [
            "the", "and", "that", "have", "for", "not", "with", "you", "this", "but", "his", "from",
            "they", "say", "her", "she", "will", "one", "all", "would", "there", "their", "what",
            "out", "about", "who", "get", "which", "go", "when", "make", "can", "like", "time",
            "no", "just", "him", "know", "take", "people", "into", "year", "your", "good", "some",
            "could", "them", "see", "other", "than", "then", "now", "look", "only", "come", "its",
            "over", "think", "also", "back", "after", "use", "two", "how", "our", "work", "first",
            "well", "way", "even", "new", "want", "because", "any", "these", "give", "day", "most", "us"
        ]
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }
            
        var freq: [String: Double] = [:]
        for w in words {
            freq[w, default: 0.0] += 1.0
        }
        return freq
    }
}
