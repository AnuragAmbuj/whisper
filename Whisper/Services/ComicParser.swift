//
//  ComicParser.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
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

/// Cross-platform comic book parser supporting CBZ format
/// CBR (RAR) support requires additional library integration
class ComicParser {
    static let shared = ComicParser()
    
    /// Supported image extensions
    private let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif"]
    
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
            .appendingPathComponent("Books")
            .appendingPathComponent(bookID.uuidString)
        
        do {
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            // Extract based on format
            if ext == "cbz" || ext == "zip" {
                try extractCBZ(from: sourceURL, to: extractDir)
            } else if ext == "cbr" || ext == "rar" {
                // CBR uses RAR format - not natively supported
                // For now, try treating it as a ZIP (some CBR files are actually ZIP)
                do {
                    try extractCBZ(from: sourceURL, to: extractDir)
                } catch {
                    print("ComicParser: CBR format not fully supported. File may use RAR compression.")
                    throw ComicParserError.unsupportedFormat
                }
            } else {
                throw ComicParserError.unsupportedFormat
            }
            
            // Find all images and sort them
            let imageURLs = try findImages(in: extractDir)
            
            guard !imageURLs.isEmpty else {
                print("ComicParser: No images found in comic")
                throw ComicParserError.noImagesFound
            }
            
            print("ComicParser: Found \(imageURLs.count) pages")
            
            // Save page list to JSON
            let relativePaths = imageURLs.map { url -> String in
                url.path.replacingOccurrences(of: extractDir.path + "/", with: "")
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
            
            // Extract title from filename
            let title = sourceURL.deletingPathExtension().lastPathComponent
            
            // Create Book
            let book = Book(
                id: bookID,
                title: title,
                author: "Unknown",
                coverImageName: coverImageName,
                content: "Comic Book - \(imageURLs.count) pages",
                format: .comic,
                url: extractDir
            )
            
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
        // Try to load from pages.json first
        let pagesURL = bookDir.appendingPathComponent("pages.json")
        if let data = try? Data(contentsOf: pagesURL),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            return paths.map { bookDir.appendingPathComponent($0) }
        }
        
        // Fallback: scan directory
        return (try? findImages(in: bookDir)) ?? []
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
            for case let fileURL as URL in enumerator {
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
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            if let data = resized.jpegData(compressionQuality: 0.8) {
                try? data.write(to: coverURL)
                return coverName
            }
        }
        #elseif canImport(AppKit)
        if let image = NSImage(contentsOfFile: imageURL.path) {
            let targetSize = NSSize(width: 300, height: 450)
            let resized = NSImage(size: targetSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: targetSize),
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .copy, fraction: 1.0)
            resized.unlockFocus()
            
            if let tiffData = resized.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? jpegData.write(to: coverURL)
                return coverName
            }
        }
        #endif
        
        // Fallback: just copy the original image
        try? FileManager.default.copyItem(at: imageURL, to: coverURL)
        return coverName
    }
}
