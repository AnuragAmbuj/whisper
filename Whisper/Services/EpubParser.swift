//
//  EpubParser.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData

/// Parsed EPUB metadata
struct EpubModel {
  let title: String
  let author: String
  let coverPath: String?
  let contentPath: String
}

/// Table of Contents item for navigation
struct TOCItem: Codable, Identifiable {
  var id = UUID()
  let title: String
  let path: String

  enum CodingKeys: String, CodingKey {
    case id, title, path
  }
}

/// EPUB parsing errors
enum EpubParserError: Error, LocalizedError {
  case fileNotFound
  case invalidEpub
  case containerNotFound
  case opfNotFound
  case parsingFailed(String)

  var errorDescription: String? {
    switch self {
    case .fileNotFound:
      return "EPUB file not found"
    case .invalidEpub:
      return "Invalid EPUB format"
    case .containerNotFound:
      return "container.xml not found in EPUB"
    case .opfNotFound:
      return "OPF file not found in EPUB"
    case .parsingFailed(let message):
      return "Parsing failed: \(message)"
    }
  }
}

/// Cross-platform EPUB parser supporting EPUB 2 and EPUB 3 formats
class EpubParser: NSObject, XMLParserDelegate {
  static let shared = EpubParser()

  // MARK: - Parsing State
  private var currentElement = ""
  private var foundTitle = ""
  private var foundAuthor = ""
  private var foundRootfile = ""

  // Manifest & Spine
  private var manifestItems: [String: String] = [:]  // ID -> Href
  private var spineItemRefs: [String] = []
  private var foundCoverID: String?

  // TOC State
  private var foundTOCID: String?
  private var tocItems: [TOCItem] = []
  private var tempNavLabel = ""
  private var tempContentSrc = ""
  private var isParsingOPF = false
  private var isParsingNCX = false
  private var isParsingNavDoc = false
  private var inNavTOC = false
  private var navLinkHref = ""
  private var navLinkText = ""

  private override init() {}

  // MARK: - Public API

  /// Parses an EPUB file and returns a Book object
  /// - Parameter sourceURL: URL of the .epub file
  /// - Returns: Parsed Book or nil if parsing fails
  func parse(sourceURL: URL) -> Book? {
    let fileManager = FileManager.default
    let bookID = UUID()

    // Validate file exists
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      print("EpubParser: File not found at \(sourceURL.path)")
      return nil
    }

    guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      return nil
    }

    let unzipDir =
      documentsDir
      .appendingPathComponent("Books")
      .appendingPathComponent(bookID.uuidString)

    do {
      // 1. Unzip EPUB
      try fileManager.createDirectory(at: unzipDir, withIntermediateDirectories: true)
      try MiniZip.shared.unzip(sourceURL: sourceURL, destinationURL: unzipDir)
      print("EpubParser: Unzipped to \(unzipDir.path)")

      // 2. Parse container.xml to find OPF location
      let containerURL = unzipDir.appendingPathComponent("META-INF/container.xml")
      guard fileManager.fileExists(atPath: containerURL.path) else {
        print("EpubParser: container.xml not found")
        throw EpubParserError.containerNotFound
      }

      resetState()
      if let parser = XMLParser(contentsOf: containerURL) {
        parser.delegate = self
        parser.parse()
      }

      guard !foundRootfile.isEmpty else {
        print("EpubParser: rootfile not found in container.xml")
        throw EpubParserError.opfNotFound
      }

      print("EpubParser: Found OPF at \(foundRootfile)")

      // 3. Parse OPF for metadata, manifest, and spine
      let opfURL = unzipDir.appendingPathComponent(foundRootfile)
      guard fileManager.fileExists(atPath: opfURL.path) else {
        print("EpubParser: OPF file not found at \(opfURL.path)")
        throw EpubParserError.opfNotFound
      }

      resetMetadata()
      isParsingOPF = true
      isParsingNCX = false
      isParsingNavDoc = false

      if let parser = XMLParser(contentsOf: opfURL) {
        parser.delegate = self
        parser.parse()
      }
      isParsingOPF = false

      print("EpubParser: Title='\(foundTitle)', Author='\(foundAuthor)'")
      print(
        "EpubParser: Manifest items: \(manifestItems.count), Spine items: \(spineItemRefs.count)")

      // 4. Extract cover image
      var coverImageName = ""
      if let coverID = foundCoverID, let href = manifestItems[coverID] {
        let coverURL = opfURL.deletingLastPathComponent().appendingPathComponent(href)
        if fileManager.fileExists(atPath: coverURL.path) {
          let ext = coverURL.pathExtension
          let newCoverName = "\(bookID.uuidString)_cover.\(ext)"
          let destURL = documentsDir.appendingPathComponent(newCoverName)

          // Remove existing if any
          try? fileManager.removeItem(at: destURL)

          do {
            try fileManager.copyItem(at: coverURL, to: destURL)
            coverImageName = newCoverName
            print("EpubParser: Extracted cover to \(newCoverName)")
          } catch {
            print("EpubParser: Failed to copy cover - \(error.localizedDescription)")
          }
        } else {
          print("EpubParser: Cover file missing at \(coverURL.path)")
        }
      } else {
        print("EpubParser: No cover ID found or href missing")
      }

      // 5. Generate spine (reading order)
      let opfDir = opfURL.deletingLastPathComponent()
      let relativeOpfPath = opfDir.path.replacingOccurrences(of: unzipDir.path, with: "")
      let prefix =
        relativeOpfPath.hasPrefix("/") ? String(relativeOpfPath.dropFirst()) : relativeOpfPath

      let chapterPaths = spineItemRefs.compactMap { idref -> String? in
        guard let href = manifestItems[idref] else { return nil }
        if prefix.isEmpty { return href }
        return prefix.isEmpty ? href : "\(prefix)/\(href)"
      }

      // Save spine to JSON
      if !chapterPaths.isEmpty {
        let spineURL = unzipDir.appendingPathComponent("spine.json")
        if let jsonData = try? JSONEncoder().encode(chapterPaths) {
          try? jsonData.write(to: spineURL)
          print("EpubParser: Saved spine with \(chapterPaths.count) chapters")
        }
      }

      // 6. Parse TOC (try EPUB 3 Nav first, then NCX)
      if let tocID = foundTOCID, let href = manifestItems[tocID] {
        let tocURL = opfURL.deletingLastPathComponent().appendingPathComponent(href)

        if fileManager.fileExists(atPath: tocURL.path) {
          let isNavDoc = href.hasSuffix(".xhtml") || href.hasSuffix(".html")

          tocItems = []
          isParsingOPF = false
          isParsingNCX = !isNavDoc
          isParsingNavDoc = isNavDoc
          inNavTOC = false

          if let parser = XMLParser(contentsOf: tocURL) {
            parser.delegate = self
            parser.parse()
          }

          // Adjust TOC paths relative to unzip root
          let tocDir = tocURL.deletingLastPathComponent()
          let tocPrefix = tocDir.path.replacingOccurrences(of: unzipDir.path, with: "")
          let cleanTocPrefix = tocPrefix.hasPrefix("/") ? String(tocPrefix.dropFirst()) : tocPrefix

          let finalTOC = tocItems.map { item -> TOCItem in
            var newPath = item.path
            // Remove fragment identifier for path resolution
            let pathWithoutFragment = newPath.components(separatedBy: "#").first ?? newPath
            if !cleanTocPrefix.isEmpty && !pathWithoutFragment.hasPrefix("/") {
              newPath =
                cleanTocPrefix.isEmpty
                ? pathWithoutFragment : "\(cleanTocPrefix)/\(pathWithoutFragment)"
            }
            return TOCItem(title: item.title, path: newPath)
          }

          // Save TOC to JSON
          if !finalTOC.isEmpty {
            let tocJsonURL = unzipDir.appendingPathComponent("toc.json")
            if let jsonData = try? JSONEncoder().encode(finalTOC) {
              try? jsonData.write(to: tocJsonURL)
              print("EpubParser: Saved TOC with \(finalTOC.count) items")
            }
          }
        }
      }

      // 7. Create and return Book
      let book = Book(
        id: bookID,
        title: foundTitle.isEmpty
          ? sourceURL.deletingPathExtension().lastPathComponent : foundTitle,
        author: foundAuthor.isEmpty ? "Unknown Author" : foundAuthor,
        coverImageName: coverImageName,
        content: "EPUB Content",
        format: .epub,
        url: unzipDir
      )

      print("EpubParser: Successfully parsed '\(book.title)'")
      return book

    } catch {
      print("EpubParser Error: \(error.localizedDescription)")
      try? fileManager.removeItem(at: unzipDir)
      return nil
    }
  }

  // MARK: - Private Helpers

  private func resetState() {
    currentElement = ""
    foundRootfile = ""
    isParsingOPF = false
    isParsingNCX = false
    isParsingNavDoc = false
  }

  private func resetMetadata() {
    foundTitle = ""
    foundAuthor = ""
    foundCoverID = nil
    foundTOCID = nil
    manifestItems = [:]
    spineItemRefs = []
    tocItems = []
  }

  // MARK: - XMLParserDelegate

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
  ) {
    currentElement = elementName

    // EPUB 3 Nav Document parsing
    if isParsingNavDoc {
      // Look for <nav epub:type="toc">
      if elementName == "nav" {
        if let epubType = attributeDict["epub:type"], epubType == "toc" {
          inNavTOC = true
        }
      }
      if inNavTOC && elementName == "a" {
        navLinkHref = attributeDict["href"] ?? ""
        navLinkText = ""
      }
      return
    }

    // NCX parsing
    if isParsingNCX {
      if elementName == "navPoint" {
        tempNavLabel = ""
        tempContentSrc = ""
      }
      if elementName == "content", let src = attributeDict["src"] {
        tempContentSrc = src
      }
      return
    }

    // Container.xml parsing
    if elementName == "rootfile", let path = attributeDict["full-path"] {
      foundRootfile = path
    }

    // OPF Parsing
    if isParsingOPF {
      // OPF Manifest parsing
      if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
        manifestItems[id] = href

        // Check for cover-image property (EPUB 3)
        if let properties = attributeDict["properties"] {
          if properties.contains("cover-image") {
            foundCoverID = id
          }
          if properties.contains("nav") {
            foundTOCID = id  // EPUB 3 Navigation Document
          }
        }

        // Check media-type for NCX (EPUB 2)
        if let mediaType = attributeDict["media-type"], mediaType == "application/x-dtbncx+xml" {
          if foundTOCID == nil {
            foundTOCID = id
          }
        }
      }

      // OPF Spine parsing
      if elementName == "spine" {
        // EPUB 2: toc attribute points to NCX
        if let toc = attributeDict["toc"], foundTOCID == nil {
          foundTOCID = toc
        }
      }
      if elementName == "itemref", let idref = attributeDict["idref"] {
        spineItemRefs.append(idref)
      }

      // Cover metadata (EPUB 2 style)
      if elementName == "meta" {
        if let name = attributeDict["name"], name == "cover",
          let content = attributeDict["content"]
        {
          foundCoverID = content
        }
      }
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {

    // Clear currentElement if it matches (fix for stuck state)
    if currentElement == elementName {
      currentElement = ""
    }

    // EPUB 3 Nav Document
    if isParsingNavDoc {
      if elementName == "nav" {
        inNavTOC = false
      }
      if inNavTOC && elementName == "a" && !navLinkHref.isEmpty {
        let title = navLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
          tocItems.append(TOCItem(title: title, path: navLinkHref))
        }
        navLinkHref = ""
        navLinkText = ""
      }
      return
    }

    // NCX parsing
    if isParsingNCX {
      if elementName == "navPoint" {
        if !tempNavLabel.isEmpty && !tempContentSrc.isEmpty {
          tocItems.append(TOCItem(title: tempNavLabel, path: tempContentSrc))
        }
        tempNavLabel = ""
        tempContentSrc = ""
      }
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // EPUB 3 Nav Document
    if isParsingNavDoc && inNavTOC {
      navLinkText += trimmed
      return
    }

    // NCX parsing
    if isParsingNCX {
      if currentElement == "text" {
        tempNavLabel += trimmed
      }
      return
    }

    // OPF metadata - ONLY if isParsingOPF is true
    if isParsingOPF {
      if currentElement == "dc:title" || currentElement == "title" {
        foundTitle += trimmed
      } else if currentElement == "dc:creator" || currentElement == "creator" {
        foundAuthor += trimmed
      }
    }
  }
}
