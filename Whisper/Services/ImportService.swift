//
//  ImportService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import PDFKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
class ImportService {
    static let shared = ImportService()
    
    private init() {}
    
    nonisolated static var supportedTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .zip]
        
        if let epub = UTType("org.idpf.epub-container") {
            types.append(epub)
        }
        if let cbz = UTType("com.macitbetter.cbz-archive") {
            types.append(cbz)
        }
        if let cbr = UTType("com.macitbetter.cbr-archive") {
            types.append(cbr)
        }
        
        return types
    }
    
    /// Imports a file from a URL and creates a Book object
    /// - Parameter sourceURL: The URL of the file to import
    /// - Returns: The imported Book, or nil if import failed
    func importFile(at sourceURL: URL) async -> Book? {
        return importFileSync(at: sourceURL)
    }
    
    private func importFileSync(at sourceURL: URL) -> Book? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            print("ImportService: File not found at \(sourceURL.path)")
            return nil
        }
        
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let booksDir = documentsDir.appendingPathComponent("Books")
        do {
            try fileManager.createDirectory(at: booksDir, withIntermediateDirectories: true)
        } catch {
            print("ImportService: Failed to create Books directory: \(error)")
            return nil
        }
        
        let ext = sourceURL.pathExtension.lowercased()
        
        switch ext {
        case "epub":
            return importEPUBSync(from: sourceURL, booksDir: booksDir)
        case "pdf":
            return importPDFSync(from: sourceURL, booksDir: booksDir, documentsDir: documentsDir)
        case "cbz", "cbr", "zip":
            return importComicSync(from: sourceURL, booksDir: booksDir)
        case "txt":
            return importTextSync(from: sourceURL, booksDir: booksDir)
        default:
            print("ImportService: Unsupported format: \(ext)")
            return nil
        }
    }
    
    private func importEPUBSync(from sourceURL: URL, booksDir: URL) -> Book? {
        let destinationURL = booksDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) && destinationURL != sourceURL {
                try fileManager.removeItem(at: destinationURL)
            }
            if destinationURL != sourceURL {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            print("ImportService: Failed to copy EPUB: \(error)")
            return nil
        }
        
        if let book = EpubParser.shared.parse(sourceURL: destinationURL) {
            book.url = destinationURL
            // Trigger automatic iCloud Drive synchronization
            CloudSyncService.shared.uploadBookToCloud(fileURL: destinationURL)
            return book
        }
        
        print("ImportService: EPUB parsing failed")
        if destinationURL != sourceURL {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        return nil
    }
    
    private func importPDFSync(from sourceURL: URL, booksDir: URL, documentsDir: URL) -> Book? {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destinationURL = booksDir.appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) && destinationURL != sourceURL {
                try fileManager.removeItem(at: destinationURL)
            }
            if destinationURL != sourceURL {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
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
        
        // Enhance with TypeSafe metadata extraction if filename is formatted with author/title
        if author == "Unknown Author" || title == sourceURL.deletingPathExtension().lastPathComponent {
            let extracted = TypeSafeService.shared.extractCleanMetadata(from: fileName)
            if title == sourceURL.deletingPathExtension().lastPathComponent && !extracted.title.isEmpty {
                title = extracted.title
            }
            if author == "Unknown Author" && extracted.author != "Unknown Author" {
                author = extracted.author
            }
        }
        
        let book = Book(
            title: title,
            author: author,
            coverImageName: coverImageName,
            content: "PDF Document - \(pageCount) pages",
            format: .pdf,
            url: destinationURL
        )
        
        // Trigger automatic iCloud Drive synchronization
        CloudSyncService.shared.uploadBookToCloud(fileURL: destinationURL)
        return book
    }
    
    private func importComicSync(from sourceURL: URL, booksDir: URL) -> Book? {
        let destinationURL = booksDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) && destinationURL != sourceURL {
                try fileManager.removeItem(at: destinationURL)
            }
            if destinationURL != sourceURL {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            print("ImportService: Failed to copy comic: \(error)")
            return nil
        }
        
        if let book = ComicParser.shared.parse(sourceURL: destinationURL) {
            if book.author == "Unknown Author" {
                let extracted = TypeSafeService.shared.extractCleanMetadata(from: destinationURL.lastPathComponent)
                if extracted.author != "Unknown Author" {
                    book.author = extracted.author
                }
            }
            book.url = destinationURL
            // Trigger automatic iCloud Drive synchronization
            CloudSyncService.shared.uploadBookToCloud(fileURL: destinationURL)
            return book
        }
        
        print("ImportService: Comic parsing failed")
        if destinationURL != sourceURL {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        return nil
    }
    
    private func importTextSync(from sourceURL: URL, booksDir: URL) -> Book? {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destinationURL = booksDir.appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) && destinationURL != sourceURL {
                try fileManager.removeItem(at: destinationURL)
            }
            if destinationURL != sourceURL {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            print("ImportService: Failed to copy text file: \(error)")
            return nil
        }
        
        let metadata = TypeSafeService.shared.extractCleanMetadata(from: fileName)
        var content = "Unable to read content"
        
        if let textContent = try? String(contentsOf: destinationURL, encoding: .utf8) {
            content = textContent
        }
        
        let book = Book(
            title: metadata.title,
            author: metadata.author,
            coverImageName: "",
            content: content,
            format: .text,
            url: destinationURL
        )
        
        // Trigger automatic iCloud Drive synchronization
        CloudSyncService.shared.uploadBookToCloud(fileURL: destinationURL)
        return book
    }
    
    private func generatePDFCover(from page: PDFPage, documentsDir: URL) -> String {
        let pageRect = page.bounds(for: .mediaBox)
        let targetSize = CGSize(width: 300, height: 400)
        let renderer = ImageRenderer()
        
        guard let image = renderer.render(page: page, originalSize: pageRect.size, targetSize: targetSize) else {
            return ""
        }
        
        let coverFileName = "cover_\(UUID().uuidString).jpg"
        let coverURL = documentsDir.appendingPathComponent(coverFileName)
        
        if renderer.saveImage(image, to: coverURL) {
            return coverFileName
        }
        
        return ""
    }
}

// MARK: - Platform Image Renderer
private class ImageRenderer {
    #if canImport(UIKit)
    func render(page: PDFPage, originalSize: CGSize, targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            
            let scaleX = targetSize.width / originalSize.width
            let scaleY = targetSize.height / originalSize.height
            let scale = min(scaleX, scaleY)
            
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (targetSize.width - scaledWidth) / 2
            let offsetY = (targetSize.height - scaledHeight) / 2
            
            ctx.cgContext.translateBy(x: offsetX, y: targetSize.height - offsetY)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
    
    func saveImage(_ image: UIImage, to url: URL) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
    #elseif canImport(AppKit)
    func render(page: PDFPage, originalSize: CGSize, targetSize: CGSize) -> NSImage? {
        let image = NSImage(size: targetSize)
        image.lockFocus()
        
        NSColor.white.set()
        NSRect(origin: .zero, size: targetSize).fill()
        
        let scaleX = targetSize.width / originalSize.width
        let scaleY = targetSize.height / originalSize.height
        let scale = min(scaleX, scaleY)
        
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let offsetX = (targetSize.width - scaledWidth) / 2
        let offsetY = (targetSize.height - scaledHeight) / 2
        
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        
        image.unlockFocus()
        return image
    }
    
    func saveImage(_ image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
    #endif
}
