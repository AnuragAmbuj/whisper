//
//  EpubGeneratorService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 25/09/26.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Converts plain text, scanned documents, and chapters into genuine,
/// standards-compliant EPUB 3 archives with navigation, styling, and covers.
final class EpubGeneratorService {
    static let shared = EpubGeneratorService()
    
    private init() {}
    
    struct ChapterInput {
        let title: String
        let content: String
    }
    
    /// Parses continuous scanned text into discrete chapters or pages.
    /// Handles "--- Page X ---", "# Chapter X", or splits text into readable sections.
    func parseTextIntoChapters(_ text: String, defaultTitle: String = "Chapter 1") -> [ChapterInput] {
        // 1. Check for page markers
        let pagePattern = "(?i)---\\s*Page\\s*(\\d+)\\s*---"
        if let regex = try? NSRegularExpression(pattern: pagePattern) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            if !matches.isEmpty {
                var chapters: [ChapterInput] = []
                var lastIndex = 0
                var currentTitle = defaultTitle
                
                for match in matches {
                    let range = match.range
                    if range.location > lastIndex {
                        let chunk = nsText.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !chunk.isEmpty {
                            chapters.append(ChapterInput(title: currentTitle, content: chunk))
                        }
                    }
                    let pageNum = nsText.substring(with: match.range(at: 1))
                    currentTitle = "Page \(pageNum)"
                    lastIndex = range.location + range.length
                }
                
                if lastIndex < nsText.length {
                    let chunk = nsText.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chunk.isEmpty {
                        chapters.append(ChapterInput(title: currentTitle, content: chunk))
                    }
                }
                if !chapters.isEmpty {
                    return chapters
                }
            }
        }
        
        // 2. Check for Markdown Chapter headings (# Chapter ...)
        let lines = text.components(separatedBy: .newlines)
        var chapters: [ChapterInput] = []
        var currentTitle = defaultTitle
        var currentLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") || trimmed.lowercased().hasPrefix("chapter ") {
                if !currentLines.isEmpty {
                    chapters.append(ChapterInput(title: currentTitle, content: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentLines.removeAll()
                }
                currentTitle = trimmed.replacingOccurrences(of: "# ", with: "").trimmingCharacters(in: .whitespaces)
            } else {
                currentLines.append(line)
            }
        }
        if !currentLines.isEmpty {
            chapters.append(ChapterInput(title: currentTitle, content: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return chapters.isEmpty ? [ChapterInput(title: defaultTitle, content: text)] : chapters
    }
    
    /// Generates a valid EPUB 3 archive and extracts it to the local book sandbox.
    #if canImport(UIKit)
    typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    typealias PlatformImage = NSImage
    #endif
    
    func generateEpub(
        title: String,
        author: String,
        chapters: [ChapterInput],
        coverImage: PlatformImage? = nil,
        bookID: UUID = UUID()
    ) throws -> (epubURL: URL, bookDir: URL, coverImageName: String) {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "EpubGenerator", code: 500, userInfo: [NSLocalizedDescriptionKey: "Document directory unavailable"])
        }
        
        let booksDir = docs.appendingPathComponent("Books", isDirectory: true)
        try fileManager.createDirectory(at: booksDir, withIntermediateDirectories: true)
        
        let safeTitle = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
        let epubURL = booksDir.appendingPathComponent("\(safeTitle).epub")
        let unzipDir = booksDir.appendingPathComponent(bookID.uuidString, isDirectory: true)
        
        // Ensure clean destination
        try? fileManager.removeItem(at: epubURL)
        try? fileManager.removeItem(at: unzipDir)
        try fileManager.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        
        var zipEntries: [MiniZip.ZipEntry] = []
        
        // 1. mimetype (MUST be first, stored uncompressed)
        let mimeData = "application/epub+zip".data(using: .utf8)!
        zipEntries.append(MiniZip.ZipEntry(path: "mimetype", data: mimeData, uncompressed: true))
        
        // 2. META-INF/container.xml
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """
        zipEntries.append(MiniZip.ZipEntry(path: "META-INF/container.xml", data: containerXML.data(using: .utf8)!))
        
        // 3. OEBPS/style.css
        let cssContent = """
        @charset "UTF-8";
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 1.5em;
            line-height: 1.6;
            color: #1a1a1a;
            background-color: transparent;
        }
        h1, h2, h3 {
            text-align: center;
            font-weight: 700;
            margin-top: 1.5em;
            margin-bottom: 0.8em;
            color: #000;
        }
        p {
            margin: 0.8em 0;
            text-align: justify;
            text-indent: 1.2em;
        }
        .page-badge {
            display: block;
            text-align: center;
            font-size: 0.8em;
            font-weight: 600;
            color: #8e8e93;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 1em;
        }
        """
        zipEntries.append(MiniZip.ZipEntry(path: "OEBPS/style.css", data: cssContent.data(using: .utf8)!))
        
        // 4. Handle Cover
        var coverImageName = ""
        var coverData: Data? = nil
        #if canImport(UIKit) && !os(macOS)
        if let cover = coverImage {
            coverData = cover.jpegData(compressionQuality: 0.85)
        } else {
            coverData = generateCoverImage(title: title, author: author)
        }
        #elseif canImport(AppKit)
        if let cover = coverImage,
           let tiff = cover.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            coverData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        } else {
            coverData = generateCoverImage(title: title, author: author)
        }
        #endif
        
        if let cData = coverData {
            zipEntries.append(MiniZip.ZipEntry(path: "OEBPS/cover.jpg", data: cData))
            let coverFilename = "\(bookID.uuidString)_cover.jpg"
            let coverDest = docs.appendingPathComponent(coverFilename)
            try? cData.write(to: coverDest)
            coverImageName = coverFilename
        }
        
        // 5. Generate Chapters XHTML
        var manifestChapterItems: [String] = []
        var spineItemRefs: [String] = []
        var navListItems: [String] = []
        var ncxNavPoints: [String] = []
        
        let validChapters = chapters.isEmpty ? [ChapterInput(title: "Chapter 1", content: "Scanned content")] : chapters
        
        for (i, chapter) in validChapters.enumerated() {
            let chapterId = "chap_\(i + 1)"
            let fileName = "chapter_\(i + 1).xhtml"
            let escTitle = escapeXML(chapter.title)
            
            // Format paragraphs
            let paragraphs = chapter.content
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "<p>\(escapeXML($0).replacingOccurrences(of: "\n", with: "<br/>"))</p>" }
                .joined(separator: "\n    ")
            
            let chapterXHTML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
                <title>\(escTitle)</title>
                <link rel="stylesheet" type="text/css" href="style.css"/>
            </head>
            <body>
                <span class="page-badge">\(escTitle)</span>
                <h2>\(escTitle)</h2>
                \(paragraphs.isEmpty ? "<p></p>" : paragraphs)
            </body>
            </html>
            """
            
            zipEntries.append(MiniZip.ZipEntry(path: "OEBPS/\(fileName)", data: chapterXHTML.data(using: .utf8)!))
            
            manifestChapterItems.append("""
                    <item id="\(chapterId)" href="\(fileName)" media-type="application/xhtml+xml"/>
            """)
            spineItemRefs.append("""
                    <itemref idref="\(chapterId)"/>
            """)
            navListItems.append("""
                    <li><a href="\(fileName)">\(escTitle)</a></li>
            """)
            ncxNavPoints.append("""
                    <navPoint id="navPoint-\(i + 1)" playOrder="\(i + 1)">
                        <navLabel><text>\(escTitle)</text></navLabel>
                        <content src="\(fileName)"/>
                    </navPoint>
            """)
        }
        
        // 6. OEBPS/nav.xhtml
        let navXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head>
            <title>\(escapeXML(title))</title>
            <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
            <nav epub:type="toc" id="toc">
                <h1>Table of Contents</h1>
                <ol>
                    \(navListItems.joined(separator: "\n        "))
                </ol>
            </nav>
        </body>
        </html>
        """
        zipEntries.append(MiniZip.ZipEntry(path: "OEBPS/nav.xhtml", data: navXHTML.data(using: .utf8)!))
        
        // 7. OEBPS/toc.ncx
        let ncxContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <head>
                <meta name="dtb:uid" content="urn:uuid:\(bookID.uuidString)"/>
                <meta name="dtb:depth" content="1"/>
                <meta name="dtb:totalPageCount" content="0"/>
                <meta name="dtb:maxPageNumber" content="0"/>
            </head>
            <docTitle><text>\(escapeXML(title))</text></docTitle>
            <navMap>
                \(ncxNavPoints.joined(separator: "\n        "))
            </navMap>
        </ncx>
        """
        zipEntries.append(MiniZip.ZipEntry(path: "OEBPS/toc.ncx", data: ncxContent.data(using: .utf8)!))
        
        // 8. OEBPS/content.opf
        let isoFormatter = ISO8601DateFormatter()
        let modifiedDate = isoFormatter.string(from: Date())
        
        var coverManifest = ""
        if coverData != nil {
            coverManifest = """
                    <item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            """
        }
        
        let opfContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>\(escapeXML(title))</dc:title>
                <dc:creator>\(escapeXML(author))</dc:creator>
                <dc:identifier id="BookID">urn:uuid:\(bookID.uuidString)</dc:identifier>
                <dc:language>en</dc:language>
                <meta property="dcterms:modified">\(modifiedDate)</meta>
                \(coverData != nil ? "<meta name=\"cover\" content=\"cover-image\"/>" : "")
            </metadata>
            <manifest>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="css" href="style.css" media-type="text/css"/>
        \(coverManifest)
        \(manifestChapterItems.joined(separator: "\n"))
            </manifest>
            <spine toc="ncx">
        \(spineItemRefs.joined(separator: "\n"))
            </spine>
        </package>
        """
        zipEntries.append(MiniZip.ZipEntry(path: "OEBPS/content.opf", data: opfContent.data(using: .utf8)!))
        
        // 9. Write out the ZIP archive (.epub)
        try MiniZip.shared.createZip(entries: zipEntries, destination: epubURL)
        
        // 10. Extract directly into the bookID unzipDir for immediate reading
        try MiniZip.shared.unzip(sourceURL: epubURL, destinationURL: unzipDir)
        
        return (epubURL, unzipDir, coverImageName)
    }
    
    /// Appends new scanned pages to an existing Book, converting/updating it into a full EPUB.
    func appendScannedPages(to book: Book, newText: String, newImages: [PlatformImage] = []) throws -> URL {
        var existingChapters = parseTextIntoChapters(book.content, defaultTitle: "Section 1")
        let startingPageNumber = existingChapters.count + 1
        let newChapters = parseTextIntoChapters(newText, defaultTitle: "Page \(startingPageNumber)")
        
        let combinedChapters = existingChapters + newChapters
        let combinedText = book.content.isEmpty ? newText : "\(book.content)\n\n--- Page \(startingPageNumber) ---\n\n\(newText)"
        
        let result = try generateEpub(
            title: book.title,
            author: book.author,
            chapters: combinedChapters,
            coverImage: newImages.first,
            bookID: book.id
        )
        
        book.content = combinedText
        book.url = result.epubURL
        book.format = .epub
        if book.coverImageName.isEmpty && !result.coverImageName.isEmpty {
            book.coverImageName = result.coverImageName
        }
        book.lastReadDate = Date()
        book.isCloudSynced = false
        book.cloudFileID = nil
        book.cloudSyncError = nil
        
        CloudSyncService.shared.uploadBookToCloud(fileURL: result.epubURL)
        BookService.shared.indexBookInSpotlight(book)
        
        return result.epubURL
    }
    
    // MARK: - Private Helpers
    
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func generateCoverImage(title: String, author: String) -> Data? {
        #if canImport(UIKit) && !os(macOS)
        let size = CGSize(width: 600, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Background gradient
            let colors = [
                UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1.0).cgColor,
                UIColor(red: 0.22, green: 0.26, blue: 0.38, alpha: 1.0).cgColor
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            
            // Border
            ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
            ctx.cgContext.setLineWidth(4)
            ctx.cgContext.stroke(CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48))
            
            // Title
            let titleFont = UIFont.systemFont(ofSize: 40, weight: .bold)
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: titleStyle
            ]
            let titleRect = CGRect(x: 48, y: 260, width: size.width - 96, height: 260)
            (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
            
            // Author
            let authorFont = UIFont.systemFont(ofSize: 22, weight: .medium)
            let authorAttrs: [NSAttributedString.Key: Any] = [
                .font: authorFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .paragraphStyle: titleStyle
            ]
            let authorRect = CGRect(x: 48, y: 540, width: size.width - 96, height: 60)
            (author as NSString).draw(in: authorRect, withAttributes: authorAttrs)
            
            // Badge
            let badgeFont = UIFont.systemFont(ofSize: 14, weight: .bold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: UIColor(red: 0.96, green: 0.58, blue: 0.27, alpha: 1.0),
                .paragraphStyle: titleStyle
            ]
            let badgeRect = CGRect(x: 48, y: 820, width: size.width - 96, height: 30)
            ("WHISPER EPUB EDITION" as NSString).draw(in: badgeRect, withAttributes: badgeAttrs)
        }
        return image.jpegData(compressionQuality: 0.85)
        #elseif canImport(AppKit)
        let size = NSSize(width: 600, height: 900)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        
        let titleFont = NSFont.boldSystemFont(ofSize: 40)
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: titleStyle
        ]
        (title as NSString).draw(in: NSRect(x: 48, y: 350, width: size.width - 96, height: 260), withAttributes: titleAttrs)
        image.unlockFocus()
        
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #else
        return nil
        #endif
    }
}
