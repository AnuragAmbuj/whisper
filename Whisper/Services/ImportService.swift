//
//  ImportService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum ImportError: Error, LocalizedError {
    case fileNotFound
    case copyFailed
    case unsupportedFormat
    case parseFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "File not found"
        case .copyFailed: return "Failed to copy file"
        case .unsupportedFormat: return "Unsupported file format"
        case .parseFailed(let message): return "Import failed: \(message)"
        }
    }
}

@MainActor
class ImportService {
    static let shared = ImportService()
    
    static let supportedTypes: [UTType] = [
        .pdf,
        .epub,
        .zip,
        UTType(filenameExtension: "cbz") ?? .zip,
        UTType(filenameExtension: "cbr") ?? .data,
        .plainText
    ]
    
    private init() {}
    
    func importFile(at sourceURL: URL) async -> Book? {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }
        
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            print("ImportService: File not found at \(sourceURL.path)")
            return nil
        }
        
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let booksDir = documentsDir.appendingPathComponent("Books", isDirectory: true)
        let coversDir = documentsDir.appendingPathComponent("Covers", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: booksDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)
        } catch {
            print("ImportService: Failed to create directories: \(error)")
            return nil
        }
        
        let ext = sourceURL.pathExtension.lowercased()
        
        switch ext {
        case "epub":
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let book = self.importEPUBSync(from: sourceURL, booksDir: booksDir)
                    DispatchQueue.main.async {
                        continuation.resume(returning: book)
                    }
                }
            }
        case "pdf":
            return importPDFSync(from: sourceURL, booksDir: booksDir, documentsDir: documentsDir)
        case "cbz", "cbr", "zip":
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let book = self.importComicSync(from: sourceURL, booksDir: booksDir)
                    DispatchQueue.main.async {
                        continuation.resume(returning: book)
                    }
                }
            }
        case "txt":
            return importTextSync(from: sourceURL, booksDir: booksDir)
        default:
            print("ImportService: Unsupported format: \(ext)")
            return nil
        }
    }
    
    private nonisolated func importEPUBSync(from sourceURL: URL, booksDir: URL) -> Book? {
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
        
        if let book = EpubParser.shared.parse(sourceURL: destinationURL) {
            try? FileManager.default.removeItem(at: destinationURL)
            return book
        }
        
        print("ImportService: EPUB parsing failed")
        try? FileManager.default.removeItem(at: destinationURL)
        return nil
    }
    
    private func importPDFSync(from sourceURL: URL, booksDir: URL, documentsDir: URL) -> Book? {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destinationURL = booksDir.appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ImportService: Failed to copy PDF: \(error)")
            return nil
        }
        
        var title = sourceURL.deletingPathExtension().lastPathComponent
        var author = "Unknown Author"
        var coverImageName = ""
        var pageCount = 0
        
        if let document = PDFDocument(url: destinationURL) {
            pageCount = document.pageCount
            
            if let metaTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
               !metaTitle.isEmpty {
                title = metaTitle
            }
            if let metaAuthor = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String,
               !metaAuthor.isEmpty {
                author = metaAuthor
            }
            
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
    
    private nonisolated func importComicSync(from sourceURL: URL, booksDir: URL) -> Book? {
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
        
        if let book = ComicParser.shared.parse(sourceURL: destinationURL) {
            try? FileManager.default.removeItem(at: destinationURL)
            return book
        }
        
        print("ImportService: Comic parsing failed")
        try? FileManager.default.removeItem(at: destinationURL)
        return nil
    }
    
    private func importTextSync(from sourceURL: URL, booksDir: URL) -> Book? {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destinationURL = booksDir.appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ImportService: Failed to copy text file: \(error)")
            return nil
        }
        
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

extension UTType {
    static let epub = UTType(filenameExtension: "epub") ?? .data
}
