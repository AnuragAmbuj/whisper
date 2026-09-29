//
//  ChapterService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 28/09/26.
//

import Foundation
import PDFKit

@MainActor
final class ChapterService {
    static let shared = ChapterService()
    
    private init() {}
    
    /// Extracts a navigable chapter list for any book across all supported formats (EPUB, PDF, Comic, Text, Audiobook).
    func extractChapters(for book: Book) -> [Chapter] {
        switch book.format ?? .text {
        case .epub:
            return extractEpubChapters(for: book)
        case .pdf:
            return extractPDFChapters(for:
                                        book)
        case .comic:
            return extractComicChapters(for: book)
        case .text:
            return extractTextChapters(for: book)
        case .audiobook:
            return extractAudiobookChapters(for: book)
        }
    }
    
    // MARK: - EPUB Chapter Extraction
    
    private func extractEpubChapters(for book: Book) -> [Chapter] {
        guard let dir = book.bookDir else { return [] }
        
        // 1. Check for toc.json
        let tocURL = dir.appendingPathComponent("toc.json")
        if let data = try? Data(contentsOf: tocURL),
           let list = try? JSONDecoder().decode([Chapter].self, from: data),
           !list.isEmpty {
            return list.enumerated().map { index, ch in
                var item = ch
                if item.pageOrLocation == 0 && index > 0 {
                    item.pageOrLocation = index
                }
                if item.subtitle == nil {
                    item.subtitle = "Chapter \(index + 1)"
                }
                return item
            }
        }
        
        // 2. Discover HTML chapters in bookDir
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var htmlFiles: [String] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            let name = fileURL.lastPathComponent.lowercased()
            if (ext == "html" || ext == "xhtml" || ext == "htm"),
               !name.contains("toc"), !name.contains("nav"), !name.hasPrefix(".") {
                let rel = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")
                htmlFiles.append(rel)
            }
        }
        htmlFiles.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        
        return htmlFiles.enumerated().map { index, path in
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let formattedTitle = filename
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            return Chapter(
                title: formattedTitle.isEmpty ? "Chapter \(index + 1)" : formattedTitle,
                path: path,
                pageOrLocation: index,
                subtitle: "Chapter \(index + 1)"
            )
        }
    }
    
    // MARK: - PDF Outline / Chapter Extraction
    
    private func extractPDFChapters(for book: Book) -> [Chapter] {
        guard let url = book.resolvedURL, let doc = PDFDocument(url: url) else { return [] }
        
        // 1. Check native PDF Outline/TOC
        if let root = doc.outlineRoot {
            var results: [Chapter] = []
            func traverse(node: PDFOutline) {
                for i in 0..<node.numberOfChildren {
                    if let child = node.child(at: i) {
                        let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !label.isEmpty {
                            var pageIdx = 0
                            if let dest = child.destination, let page = dest.page {
                                pageIdx = doc.index(for: page)
                            } else if let actionGoTo = child.action as? PDFActionGoTo, let page = actionGoTo.destination.page {
                                pageIdx = doc.index(for: page)
                            }
                            results.append(Chapter(
                                title: label,
                                path: "page:\(pageIdx)",
                                pageOrLocation: pageIdx,
                                subtitle: "Page \(pageIdx + 1)"
                            ))
                        }
                        traverse(node: child)
                    }
                }
            }
            traverse(node: root)
            if !results.isEmpty { return results }
        }
        
        // 2. Fallback: Generate page sections
        let count = doc.pageCount
        guard count > 0 else { return [] }
        if count <= 30 {
            return (0..<count).map { idx in
                Chapter(
                    title: "Page \(idx + 1)",
                    path: "page:\(idx)",
                    pageOrLocation: idx,
                    subtitle: "Page \(idx + 1) of \(count)"
                )
            }
        } else {
            // Group into 10-page sections
            var sections: [Chapter] = []
            var current = 0
            while current < count {
                let end = min(current + 10, count)
                sections.append(Chapter(
                    title: "Pages \(current + 1)–\(end)",
                    path: "page:\(current)",
                    pageOrLocation: current,
                    subtitle: "Page \(current + 1) of \(count)"
                ))
                current += 10
            }
            return sections
        }
    }
    
    // MARK: - Comic Chapter / Page Extraction
    
    private func extractComicChapters(for book: Book) -> [Chapter] {
        guard let dir = book.bookDir else { return [] }
        let pagesURL = dir.appendingPathComponent("pages.json")
        var pageCount = 0
        if let data = try? Data(contentsOf: pagesURL),
           let pages = try? JSONDecoder().decode([String].self, from: data) {
            pageCount = pages.count
        }
        
        if pageCount == 0 {
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
                let imgExts = Set(["jpg", "jpeg", "png", "webp"])
                while let fileURL = enumerator.nextObject() as? URL {
                    if imgExts.contains(fileURL.pathExtension.lowercased()) {
                        pageCount += 1
                    }
                }
            }
        }
        
        guard pageCount > 0 else {
            return [
                Chapter(title: "Cover", path: "page:0", pageOrLocation: 0, subtitle: "Page 1")
            ]
        }
        
        return (0..<pageCount).map { idx in
            let title = idx == 0 ? "Cover" : "Page \(idx + 1)"
            return Chapter(
                title: title,
                path: "page:\(idx)",
                pageOrLocation: idx,
                subtitle: "Page \(idx + 1) of \(pageCount)"
            )
        }
    }
    
    // MARK: - Text / Markdown Chapter Extraction
    
    private func extractTextChapters(for book: Book) -> [Chapter] {
        let lines = book.content.components(separatedBy: "\n")
        var chapters: [Chapter] = []
        
        let headerPrefixes = ["# ", "## ", "### "]
        let romanRegex = try? NSRegularExpression(
            pattern: #"^(?:chapter|part|book|section|act|scene)\s+([0-9ivxlcdm]+)"#,
            options: .caseInsensitive
        )
        
        for (lineIdx, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            var matchedTitle: String? = nil
            for prefix in headerPrefixes {
                if trimmed.hasPrefix(prefix) {
                    matchedTitle = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            
            if matchedTitle == nil, let regex = romanRegex {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    matchedTitle = trimmed
                }
            }
            
            if let title = matchedTitle, !title.isEmpty {
                chapters.append(Chapter(
                    title: title,
                    path: "line:\(lineIdx)",
                    pageOrLocation: lineIdx,
                    subtitle: "Line \(lineIdx + 1)"
                ))
            }
        }
        
        if chapters.isEmpty {
            if lines.count > 60 {
                var chunkLine = 0
                var chunkNum = 1
                while chunkLine < lines.count {
                    chapters.append(Chapter(
                        title: "Section \(chunkNum)",
                        path: "line:\(chunkLine)",
                        pageOrLocation: chunkLine,
                        subtitle: "Lines \(chunkLine + 1)–\(min(chunkLine + 60, lines.count))"
                    ))
                    chunkLine += 60
                    chunkNum += 1
                }
            } else {
                chapters.append(Chapter(
                    title: "Start of Document",
                    path: "line:0",
                    pageOrLocation: 0,
                    subtitle: "Line 1"
                ))
            }
        }
        
        return chapters
    }
    
    // MARK: - Audiobook Chapter Extraction
    
    private func extractAudiobookChapters(for book: Book) -> [Chapter] {
        if AudiobookPlayerService.shared.currentBook?.id == book.id && !AudiobookPlayerService.shared.chapters.isEmpty {
            return AudiobookPlayerService.shared.chapters.map { ch in
                Chapter(
                    title: ch.title,
                    path: "time:\(Int(ch.startTime))",
                    pageOrLocation: Int(ch.startTime),
                    subtitle: AudiobookPlayerService.formatTime(ch.startTime)
                )
            }
        }
        
        // Parse cues or lines with timestamps from book.content
        let lines = book.content.components(separatedBy: "\n")
        let timeRegex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#, options: [])
        var parsed: [Chapter] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let regex = timeRegex,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let r1 = Range(match.range(at: 1), in: trimmed),
               let r2 = Range(match.range(at: 2), in: trimmed),
               let minVal = Int(trimmed[r1]),
               let secVal = Int(trimmed[r2]) {
                let totalSecs = minVal * 60 + secVal
                let title = trimmed.replacingOccurrences(of: "•", with: "").trimmingCharacters(in: .whitespaces)
                parsed.append(Chapter(
                    title: title,
                    path: "time:\(totalSecs)",
                    pageOrLocation: totalSecs,
                    subtitle: String(format: "%02d:%02d", minVal, secVal)
                ))
            }
        }
        
        if !parsed.isEmpty { return parsed }
        
        // Default standard chapters for sample audiobooks
        return [
            Chapter(title: "Chapter 1: Introduction", path: "time:0", pageOrLocation: 0, subtitle: "00:00"),
            Chapter(title: "Chapter 2: Tactical Principles", path: "time:300", pageOrLocation: 300, subtitle: "05:00"),
            Chapter(title: "Chapter 3: Strategic Maneuvers", path: "time:600", pageOrLocation: 600, subtitle: "10:00"),
            Chapter(title: "Chapter 4: Energy & Timing", path: "time:900", pageOrLocation: 900, subtitle: "15:00"),
            Chapter(title: "Chapter 5: Concluding Insights", path: "time:1200", pageOrLocation: 1200, subtitle: "20:00")
        ]
    }
}
