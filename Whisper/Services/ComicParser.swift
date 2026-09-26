//
//  ComicParser.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Errors for comic book parsing
enum ComicParserError: Error, LocalizedError {
    case fileNotFound
    case invalidArchive
    case noImagesFound
    case unsupportedFormat
    case extractionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Comic book file not found"
        case .invalidArchive:
            return "Invalid comic book archive"
        case .noImagesFound:
            return "No images found in comic book"
        case .unsupportedFormat:
            return "Unsupported comic book format (CBR requires additional support)"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        }
    }
}

/// Metadata extracted from standard ComicRack ComicInfo.xml
struct ComicMetadata: Sendable {
    var title: String = ""
    var series: String = ""
    var number: String = ""
    var summary: String = ""
    var writer: String = ""
    var penciller: String = ""
    var characters: [String] = []
    var teams: [String] = []
    var genre: String = ""
    var notes: String = ""
}

/// Cross-platform comic book parser supporting CBZ format and ComicRack ComicInfo.xml metadata + Apple Vision OCR
class ComicParser {
    static let shared = ComicParser()
    
    /// Supported image extensions
    private let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "avif"]
    
    private init() {}
    
    // MARK: - Public API
    
    /// Parses a comic book file and returns a Book object
    /// - Parameter sourceURL: URL of the comic book file (.cbz or .cbr)
    /// - Returns: Parsed Book or nil if parsing fails
    func parse(sourceURL: URL) -> Book? {
        let fileManager = FileManager.default
        let bookID = UUID()
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            print("ComicParser: File not found at \(sourceURL.path)")
            return nil
        }
        
        let ext = sourceURL.pathExtension.lowercased()
        
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let extractDir = documentsDir
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            // Extract based on format
            if ext == "cbz" || ext == "zip" {
                try extractCBZ(from: sourceURL, to: extractDir)
            } else if ext == "cbr" || ext == "rar" {
                // CBR uses RAR format - try ZIP first in case it was a renamed CBZ
                do {
                    try extractCBZ(from: sourceURL, to: extractDir)
                } catch {
                    print("ComicParser: CBR format not fully supported. File may use RAR compression.")
                    throw ComicParserError.unsupportedFormat
                }
            } else {
                throw ComicParserError.unsupportedFormat
            }
            
            // Parse ComicInfo.xml if present
            let metadata = parseComicInfoXML(in: extractDir)
            
            // Find all images and sort them
            let imageURLs = try findImages(in: extractDir)
            
            guard !imageURLs.isEmpty else {
                print("ComicParser: No images found in comic")
                throw ComicParserError.noImagesFound
            }
            
            print("ComicParser: Found \(imageURLs.count) pages")
            
            // Save page list to JSON using standardized relative paths
            let baseStandardPath = extractDir.standardizedFileURL.path
            let relativePaths = imageURLs.map { url -> String in
                let standardPath = url.standardizedFileURL.path
                if standardPath.hasPrefix(baseStandardPath) {
                    var rel = String(standardPath.dropFirst(baseStandardPath.count))
                    if rel.hasPrefix("/") { rel.removeFirst() }
                    return rel
                }
                return url.lastPathComponent
            }
            
            let pagesURL = extractDir.appendingPathComponent("pages.json")
            if let jsonData = try? JSONEncoder().encode(relativePaths) {
                try? jsonData.write(to: pagesURL)
            }
            
            // Generate cover from first image
            var coverImageName = ""
            if let firstImage = imageURLs.first {
                coverImageName = generateCover(from: firstImage, bookID: bookID, documentsDir: documentsDir)
            }
            
            // Determine title, author, and description from ComicInfo.xml or fallback to filename
            var title = sourceURL.deletingPathExtension().lastPathComponent
            var author = "Unknown"
            var initialContent = ""
            
            if let meta = metadata {
                if !meta.title.isEmpty {
                    title = meta.title
                } else if !meta.series.isEmpty {
                    title = meta.number.isEmpty ? meta.series : "\(meta.series) #\(meta.number)"
                }
                
                if !meta.writer.isEmpty {
                    author = meta.writer
                }
                
                if !meta.summary.isEmpty {
                    initialContent = meta.summary
                }
            }
            
            // Create Book
            let book = Book(
                id: bookID,
                title: title,
                author: author,
                coverImageName: coverImageName,
                content: initialContent.isEmpty ? "Comic Book - \(imageURLs.count) pages" : initialContent,
                format: .comic,
                url: extractDir
            )
            
            // Asynchronously prewarm OCR text extraction in the background
            Task.detached(priority: .utility) { [weak self] in
                _ = self?.extractTextFromComic(bookDir: extractDir)
            }
            
            print("ComicParser: Successfully parsed '\(title)' with \(imageURLs.count) pages")
            return book
            
        } catch {
            print("ComicParser Error: \(error.localizedDescription)")
            try? fileManager.removeItem(at: extractDir)
            return nil
        }
    }
    
    /// Lists pages in an extracted comic directory
    /// - Parameter bookDir: URL of the extracted comic directory
    /// - Returns: Array of page image URLs sorted by name
    func getPages(from bookDir: URL) -> [URL] {
        let fileManager = FileManager.default
        
        // 1. Try to load from pages.json first
        let pagesURL = bookDir.appendingPathComponent("pages.json")
        if let data = try? Data(contentsOf: pagesURL),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            let urls = paths.map { relPath -> URL in
                if relPath.hasPrefix("/") {
                    let candidate = URL(fileURLWithPath: relPath)
                    if fileManager.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                    let fileName = (relPath as NSString).lastPathComponent
                    return bookDir.appendingPathComponent(fileName)
                }
                return bookDir.appendingPathComponent(relPath)
            }
            
            let validURLs = urls.filter { fileManager.fileExists(atPath: $0.path) }
            if !validURLs.isEmpty {
                return validURLs
            }
        }
        
        // 2. Fallback: scan directory directly
        return (try? findImages(in: bookDir)) ?? []
    }
    
    // MARK: - Comic Metadata & ComicInfo.xml Parsing
    
    /// Parses ComicRack ComicInfo.xml if present in the comic's directory
    func parseComicInfoXML(in directory: URL) -> ComicMetadata? {
        let fileManager = FileManager.default
        var xmlURL: URL? = directory.appendingPathComponent("ComicInfo.xml")
        
        if !fileManager.fileExists(atPath: xmlURL!.path) {
            // Search subdirectories
            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                while let file = enumerator.nextObject() as? URL {
                    if file.lastPathComponent.lowercased() == "comicinfo.xml" {
                        xmlURL = file
                        break
                    }
                }
            }
        }
        
        guard let validURL = xmlURL, fileManager.fileExists(atPath: validURL.path),
              let xmlString = try? String(contentsOf: validURL, encoding: .utf8) else {
            return nil
        }
        
        var meta = ComicMetadata()
        
        func extractTag(_ tag: String) -> String {
            let pattern = "<\(tag)>([\\s\\S]*?)</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
               let range = Range(match.range(at: 1), in: xmlString) {
                return String(xmlString[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }
        
        meta.title = extractTag("Title")
        meta.series = extractTag("Series")
        meta.number = extractTag("Number")
        meta.summary = extractTag("Summary")
        meta.writer = extractTag("Writer")
        meta.penciller = extractTag("Penciller")
        meta.genre = extractTag("Genre")
        meta.notes = extractTag("Notes")
        
        let chars = extractTag("Characters")
        if !chars.isEmpty {
            meta.characters = chars.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        
        let teams = extractTag("Teams")
        if !teams.isEmpty {
            meta.teams = teams.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        
        return meta
    }
    
    // MARK: - Comic OCR & Searchable Content Extraction
    
    /// Extracts full readable dialogue, narration, and metadata from a comic book
    /// Uses cached ocr_transcript.txt if present, or performs Apple Vision Neural OCR on pages.
    func extractTextFromComic(bookDir: URL) -> String {
        let fileManager = FileManager.default
        let transcriptURL = bookDir.appendingPathComponent("ocr_transcript.txt")
        
        // 1. Check if previously transcribed and contains metadata
        if fileManager.fileExists(atPath: transcriptURL.path),
           let cached = try? String(contentsOf: transcriptURL, encoding: .utf8),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if cached.contains("[Metadata]") {
                return cached
            }
        }
        
        // 2. Collect ComicInfo.xml metadata if present
        var sections: [String] = []
        let metadata = parseComicInfoXML(in: bookDir)
        if let meta = metadata {
            var metaHeader: [String] = ["[Metadata]"]
            if !meta.title.isEmpty { metaHeader.append("Title: \(meta.title)") }
            if !meta.series.isEmpty { metaHeader.append("Series: \(meta.series) #\(meta.number)") }
            if !meta.writer.isEmpty { metaHeader.append("Writer: \(meta.writer)") }
            if !meta.characters.isEmpty { metaHeader.append("Characters: \(meta.characters.joined(separator: ", "))") }
            if !meta.summary.isEmpty { metaHeader.append("Summary: \(meta.summary)") }
            sections.append(metaHeader.joined(separator: "\n"))
        }

        // If transcript exists, combine with metadata
        if fileManager.fileExists(atPath: transcriptURL.path),
           let cached = try? String(contentsOf: transcriptURL, encoding: .utf8),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(cached)
            let combined = sections.joined(separator: "\n\n")
            return combined
        }
        
        // 3. Perform Apple Vision Neural OCR on comic pages
        let pages = getPages(from: bookDir)
        let sampleLimit = min(pages.count, 35) // OCR up to 35 pages for performance
        
        for index in 0..<sampleLimit {
            let pageURL = pages[index]
            let pageText = performOCR(on: pageURL)
            if !pageText.isEmpty {
                sections.append("[Page \(index + 1)]\n\(pageText)")
            }
        }
        
        let combined = sections.joined(separator: "\n\n")
        
        // Save to cache file so subsequent searches and AI summaries are instant
        if !combined.isEmpty {
            try? combined.write(to: transcriptURL, atomically: true, encoding: .utf8)
        }
        
        return combined
    }
    
    /// Performs Apple Vision on-device OCR on a single comic image
    func performOCR(on imageURL: URL) -> String {
        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: imageURL.path),
              let cgImage = image.cgImage else {
            return ""
        }
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOfFile: imageURL.path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        #else
        return ""
        #endif
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observations = request.results else { return "" }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
    
    // MARK: - Private Methods
    
    private func extractCBZ(from sourceURL: URL, to destinationURL: URL) throws {
        try MiniZip.shared.unzip(sourceURL: sourceURL, destinationURL: destinationURL)
    }
    
    private func findImages(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var imageURLs: [URL] = []
        
        // Use deep enumeration to find all images
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if imageExtensions.contains(ext) {
                    // Skip macOS resource fork files
                    let fileName = fileURL.lastPathComponent
                    if !fileName.hasPrefix("._") && !fileName.hasPrefix(".") {
                        imageURLs.append(fileURL)
                    }
                }
            }
        }
        
        // Sort by path (natural sort for page ordering)
        imageURLs.sort { url1, url2 in
            url1.path.localizedStandardCompare(url2.path) == .orderedAscending
        }
        
        return imageURLs
    }
    
    private func generateCover(from imageURL: URL, bookID: UUID, documentsDir: URL) -> String {
        let coverName = "\(bookID.uuidString)_cover.jpg"
        let coverURL = documentsDir.appendingPathComponent(coverName)
        
        #if canImport(UIKit)
        if let image = UIImage(contentsOfFile: imageURL.path) {
            // Resize to cover size
            let targetSize = CGSize(width: 300, height: 450)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let coverData = renderer.jpegData(withCompressionQuality: 0.8) { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            try? coverData.write(to: coverURL)
            return coverName
        }
        #elseif canImport(AppKit)
        if let image = NSImage(contentsOfFile: imageURL.path) {
            let targetSize = NSSize(width: 300, height: 450)
            let resizedImage = NSImage(size: targetSize)
            resizedImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: targetSize))
            resizedImage.unlockFocus()
            
            if let tiffData = resizedImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? jpegData.write(to: coverURL)
                return coverName
            }
        }
        #endif
        
        return ""
    }
}
