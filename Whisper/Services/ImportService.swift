//
//  ImportService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Import errors for user feedback
enum ImportError: Error, LocalizedError {
    case fileNotFound
    case copyFailed
    case unsupportedFormat
    case parseFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .copyFailed:
            return "Failed to copy file"
        case .unsupportedFormat:
            return "Unsupported file format"
        case .parseFailed(let message):
            return "Import failed: \(message)"
        }
    }
}

/// Unified import service for all supported book formats
/// Supports: PDF, EPUB, CBZ, CBR, TXT
class ImportService {
    static let shared = ImportService()
    
    /// Supported file types for import
    static let supportedTypes: [UTType] = [
        .pdf,
        .epub,
        .zip,  // CBZ files often use .zip extension
        UTType(filenameExtension: "cbz") ?? .zip,
        UTType(filenameExtension: "cbr") ?? .data,
        .plainText
    ]
    
    private init() {}
    
    // MARK: - Public API
    
    /// Imports a file and returns the created Book object
    /// - Parameter sourceURL: URL of the file to import
    /// - Returns: Book object if successful, nil otherwise
    func importFile(at sourceURL: URL) -> Book? {
        // Access security scoped resource
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }
        
        let fileManager = FileManager.default
        
        // Validate file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            print("ImportService: File not found at \(sourceURL.path)")
            return nil
        }
        
        // Get documents directory
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        // Create necessary directories
        let booksDir = documentsDir.appendingPathComponent("Books", isDirectory: true)
        let coversDir = documentsDir.appendingPathComponent("Covers", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: booksDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)
        } catch {
            print("ImportService: Failed to create directories: \(error)")
            return nil
        }
        
        // Determine format and process accordingly
        let ext = sourceURL.pathExtension.lowercased()
        
        switch ext {
        case "epub":
            return importEPUB(from: sourceURL, booksDir: booksDir)
            
        case "pdf":
            return importPDF(from: sourceURL, booksDir: booksDir, documentsDir: documentsDir)
            
        case "cbz", "cbr", "zip":
            return importComic(from: sourceURL, booksDir: booksDir, ext: ext)
            
        case "txt":
            return importText(from: sourceURL, booksDir: booksDir)
            
        default:
            print("ImportService: Unsupported format: \(ext)")
            return nil
        }
    }
    
    // MARK: - Format-Specific Import Methods
    
    private func importEPUB(from sourceURL: URL, booksDir: URL) -> Book? {
        // Copy to Books directory first
        let destinationURL = booksDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ImportService: Failed to copy EPUB: \(error)")
            return nil
        }
        
        // Use EpubParser
        if let book = EpubParser.shared.parse(sourceURL: destinationURL) {
            // Delete the copied .epub since EpubParser extracts to its own folder
            try? FileManager.default.removeItem(at: destinationURL)
            return book
        }
        
        // Fallback if parsing fails
        print("ImportService: EPUB parsing failed")
        try? FileManager.default.removeItem(at: destinationURL)
        return nil
    }
    
    private func importPDF(from sourceURL: URL, booksDir: URL, documentsDir: URL) -> Book? {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destinationURL = booksDir.appendingPathComponent(fileName)
        
        // Copy file
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ImportService: Failed to copy PDF: \(error)")
            return nil
        }
        
        // Extract metadata
        var title = sourceURL.deletingPathExtension().lastPathComponent
        var author = "Unknown Author"
        var coverImageName = ""
        var pageCount = 0
        
        if let document = PDFDocument(url: destinationURL) {
            pageCount = document.pageCount
            
            // Extract metadata
            if let metaTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
               !metaTitle.isEmpty {
                title = metaTitle
            }
            if let metaAuthor = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String,
               !metaAuthor.isEmpty {
                author = metaAuthor
            }
            
            // Generate cover thumbnail
            if let page = document.page(at: 0) {
                coverImageName = generatePDFCover(from: page, documentsDir: documentsDir)
            }
        }
        
        return Book(
            title: title,
            author: author,
            coverImageName: coverImageName,
            content: "PDF Document - \(pageCount) pages",
            format: .pdf,
            url: destinationURL
        )
    }
    
    private func importComic(from sourceURL: URL, booksDir: URL, ext: String) -> Book? {
        // Copy to Books directory first
        let destinationURL = booksDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ImportService: Failed to copy comic: \(error)")
            return nil
        }
        
        // Use ComicParser
        if let book = ComicParser.shared.parse(sourceURL: destinationURL) {
            // Delete the copied archive since ComicParser extracts to its own folder
            try? FileManager.default.removeItem(at: destinationURL)
            return book
        }
        
        // Fallback if parsing fails
        print("ImportService: Comic parsing failed")
        try? FileManager.default.removeItem(at: destinationURL)
        return nil
    }
    
    private func importText(from sourceURL: URL, booksDir: URL) -> Book? {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destinationURL = booksDir.appendingPathComponent(fileName)
        
        // Copy file
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ImportService: Failed to copy text file: \(error)")
            return nil
        }
        
        // Read content
        let title = sourceURL.deletingPathExtension().lastPathComponent
        var content = "Unable to read content"
        
        if let textContent = try? String(contentsOf: destinationURL, encoding: .utf8) {
            content = textContent
        }
        
        return Book(
            title: title,
            author: "Unknown Author",
            coverImageName: "",
            content: content,
            format: .text,
            url: destinationURL
        )
    }
    
    // MARK: - Helper Methods
    
    private func generatePDFCover(from page: PDFPage, documentsDir: URL) -> String {
        let coverName = UUID().uuidString + "_cover.png"
        let coverURL = documentsDir.appendingPathComponent(coverName)
        
        let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 450), for: .mediaBox)
        
        #if canImport(UIKit)
        if let data = thumbnail.pngData() {
            try? data.write(to: coverURL)
            return coverName
        }
        #elseif canImport(AppKit)
        if let tiffData = thumbnail.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: coverURL)
            return coverName
        }
        #endif
        
        return ""
    }
}

// MARK: - UTType Extensions
extension UTType {
    static let epub = UTType(filenameExtension: "epub") ?? .data
}
