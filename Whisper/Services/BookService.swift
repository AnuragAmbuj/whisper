//
//  BookService.swift
//  Whisper
//
//  Created by Anurag Ambuj on 29/12/25.
//

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import PDFKit

class BookService {
  static let shared = BookService()

  private init() {}

  func seedBooks(context: ModelContext) {
    let books = generateRichSampleBooks()
    for book in books {
      context.insert(book)
    }
    try? context.save()
  }

  func checkForSeeding(context: ModelContext) {
    let descriptor = FetchDescriptor<Book>()
    do {
      let existingBooks = try context.fetch(descriptor)
      if existingBooks.isEmpty {
        seedBooks(context: context)
      } else {
        var didMigrate = false
        for book in existingBooks {
          if book.format == nil {
            book.format = .text
            didMigrate = true
          }
        }
        if didMigrate {
          try? context.save()
        }
      }
    } catch {
      print("Error checking for existing books: \(error)")
    }
  }

  func generateRichSampleBooks() -> [Book] {
    var books: [Book] = []

    // 1. Text: Pride and Prejudice
    let prideBook = Book(
      title: "Pride and Prejudice",
      author: "Jane Austen",
      coverImageName: "",
      content: prideAndPrejudiceSampleText,
      progress: 0.15,
      format: .text
    )
    prideBook.addBookmark(Bookmark(pageOrLocation: 15, note: "Mr. Bennet's witty response"))
    books.append(prideBook)

    // 2. Text: The Time Machine
    let timeMachineBook = Book(
      title: "The Time Machine",
      author: "H.G. Wells",
      coverImageName: "",
      content: timeMachineSampleText,
      progress: 0.0,
      format: .text
    )
    books.append(timeMachineBook)

    // 3. PDF: Whisper User Guide
    if let pdfURL = createSamplePDF() {
      let pdfBook = Book(
        title: "Whisper User Guide",
        author: "Whisper Team",
        coverImageName: "",
        content: "Complete handbook for the Whisper liquid glass reader, covering file import, gesture navigation, bookmarking, and visual customization.",
        progress: 0.0,
        format: .pdf,
        url: pdfURL
      )
      pdfBook.addBookmark(Bookmark(pageOrLocation: 0, note: "Introduction and Features"))
      books.append(pdfBook)
    }

    // 4. Comic: The Cosmic Odyssey
    let comicBook = createSampleComic()
    books.append(comicBook)

    // 5. EPUB: Alice's Adventures in Wonderland
    let epubBook = createSampleEPUB()
    books.append(epubBook)

    return books
  }

  // MARK: - Sample Data Generators

  private var prideAndPrejudiceSampleText: String {
    """
    Chapter 1

    It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.

    However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.

    "My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"

    Mr. Bennet replied that he had not.

    "But it is," returned she; "for Mrs. Long has just been here, and she told me all about it."

    Mr. Bennet made no answer.

    "Do you not want to know who has taken it?" cried his wife impatiently.

    "You want to tell me, and I have no objection to hearing it."

    This was invitation enough.

    "Why, my dear, you must know, Mrs. Long says that Netherfield is taken by a young man of large fortune from the north of England; that he came down on Monday in a chaise and four to see the place, and was so much delighted with it, that he agreed with Mr. Morris immediately; that he is to take possession before Michaelmas, and some of his servants are to be in the house by the end of next week."

    "What is his name?"

    "Bingley."

    "Is he married or single?"

    "Oh! Single, my dear, to be sure! A single man of large fortune; four or five thousand a year. What a fine thing for our girls!"

    "How so? How can it affect them?"

    "My dear Mr. Bennet," replied his wife, "how can you be so tiresome! You must know that I am thinking of his marrying one of them."
    """
  }

  private var timeMachineSampleText: String {
    """
    Chapter 1

    The Time Traveller (for so it will be convenient to speak of him) was expounding a recondite matter to us. His grey eyes shone and twinkled, and his usually pale face was flushed and animated. The fire burnt brightly, and the soft radiance of the incandescent lights in the lilies of silver caught the bubbles that flashed and passed in our glasses.

    "You must follow me carefully. I shall have to controvert one or two ideas that are almost universally accepted. The geometry, for instance, they taught you at school is founded on a misconception."

    "Is not that rather a large thing to expect us to begin upon?" said Filby, an argumentative person with red hair.

    "I do not mean to ask you to accept anything without reasonable ground for it. You will soon admit as much as I need from you. You know of course that a mathematical line, a line of thickness nil, has no real existence. They taught you that? Neither has a mathematical plane. These things are mere abstractions."

    "That is all right," said the Psychologist.

    "Nor, having only length, breadth, and thickness, can a cube have a real existence."

    "There I object," said Filby. "Of course a solid body may exist. All real things—"

    "So most people think. But wait a moment. Can an instantaneous cube exist?"

    "Don't follow you," said Filby.

    "Can a cube that does not last for any time at all, have a real existence?"
    """
  }

  private func createSamplePDF() -> URL? {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }
    let pdfURL = docs.appendingPathComponent("Whisper_User_Guide.pdf")

    #if canImport(UIKit)
    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

    let data = renderer.pdfData { context in
      // Page 1: Welcome
      context.beginPage()
      drawPDFHeader(title: "Whisper Reader", subtitle: "User Guide & Architecture", in: pageRect)
      drawPDFSection(
        title: "Liquid Glass Experience",
        body: "Whisper is engineered around fluid visual materials, dynamic light dispersion, and immersive typography. Built natively with SwiftData and SwiftUI, it delivers a seamless reading sanctuary across iPhone, iPad, and Mac.",
        yOffset: 200,
        pageRect: pageRect
      )
      drawPDFSection(
        title: "Multi-Format Support",
        body: "Whisper natively supports EPUB 3, PDFKit documents, CBZ/CBR comic books, and formatted plain text files with automatic spine indexing and deep table-of-contents navigation.",
        yOffset: 340,
        pageRect: pageRect
      )

      // Page 2: Reader Controls
      context.beginPage()
      drawPDFHeader(title: "Reader Capabilities", subtitle: "Gestures & Customization", in: pageRect)
      drawPDFSection(
        title: "Appearance Controls",
        body: "Tap the typography icon in any reader view to configure theme palettes: Default glass, Pure Dark, Sepia parchment, and Clean Light. Adjust font scaling and line spacing in real time.",
        yOffset: 200,
        pageRect: pageRect
      )
      drawPDFSection(
        title: "Smart Bookmarks",
        body: "Tap the bookmark icon to mark your current page or chapter. Jump back to any saved bookmark from the bookmarks drawer at any time.",
        yOffset: 340,
        pageRect: pageRect
      )
    }

    try? data.write(to: pdfURL)
    return pdfURL
    #else
    return nil
    #endif
  }

  #if canImport(UIKit)
  private func drawPDFHeader(title: String, subtitle: String, in rect: CGRect) {
    let titleAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: 28),
      .foregroundColor: UIColor.label
    ]
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 16),
      .foregroundColor: UIColor.secondaryLabel
    ]

    title.draw(at: CGPoint(x: 54, y: 72), withAttributes: titleAttributes)
    subtitle.draw(at: CGPoint(x: 54, y: 110), withAttributes: subtitleAttributes)

    // Decorative line
    let path = UIBezierPath()
    path.move(to: CGPoint(x: 54, y: 145))
    path.addLine(to: CGPoint(x: rect.width - 54, y: 145))
    UIColor.separator.setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  private func drawPDFSection(title: String, body: String, yOffset: CGFloat, pageRect: CGRect) {
    let titleAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: 20),
      .foregroundColor: UIColor.systemCyan
    ]
    let bodyAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 14),
      .foregroundColor: UIColor.label
    ]

    title.draw(at: CGPoint(x: 54, y: yOffset), withAttributes: titleAttributes)

    let textRect = CGRect(x: 54, y: yOffset + 32, width: pageRect.width - 108, height: 100)
    body.draw(in: textRect, withAttributes: bodyAttributes)
  }
  #endif

  private func createSampleComic() -> Book {
    let comicID = UUID()
    let comicBook = Book(
      id: comicID,
      title: "The Cosmic Odyssey",
      author: "Whisper Studios",
      coverImageName: "",
      content: "An interstellar voyage beyond the frontiers of the solar system. Issue #1: First Contact.",
      progress: 0.0,
      format: .comic
    )

    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return comicBook
    }
    let comicDir = docs.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(comicID.uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: comicDir, withIntermediateDirectories: true)

    let pageNames = ["page1.png", "page2.png", "page3.png", "page4.png"]

    #if canImport(UIKit)
    let titles = [
      ("THE COSMIC ODYSSEY", "Chapter 1: The Departure", UIColor(red: 0.1, green: 0.15, blue: 0.35, alpha: 1.0)),
      ("ORBITAL STATION AETHEL", "Systems Nominal • Warp Core Primed", UIColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1.0)),
      ("DEEP SPACE TRANSIT", "Entering Sector 9 • Sensors Detecting Anomaly", UIColor(red: 0.2, green: 0.1, blue: 0.35, alpha: 1.0)),
      ("FIRST CONTACT", "The Signal is Received • To Be Continued...", UIColor(red: 0.05, green: 0.25, blue: 0.3, alpha: 1.0))
    ]

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200))
    for (index, pageName) in pageNames.enumerated() {
      let pageData = renderer.pngData { ctx in
        let rect = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let info = titles[index]

        // Background gradient
        info.2.setFill()
        ctx.fill(rect)

        // Comic panel borders
        let panelRect = rect.insetBy(dx: 40, dy: 40)
        UIColor.white.withAlphaComponent(0.15).setFill()
        ctx.fill(panelRect)

        let border = UIBezierPath(rect: panelRect)
        UIColor.white.withAlphaComponent(0.6).setStroke()
        border.lineWidth = 4
        border.stroke()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
          .font: UIFont.boldSystemFont(ofSize: 36),
          .foregroundColor: UIColor.white
        ]
        info.0.draw(at: CGPoint(x: 64, y: 80), withAttributes: titleAttrs)

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: 20),
          .foregroundColor: UIColor.cyan
        ]
        info.1.draw(at: CGPoint(x: 64, y: 140), withAttributes: subAttrs)

        // Page number
        let pageNumAttrs: [NSAttributedString.Key: Any] = [
          .font: UIFont.boldSystemFont(ofSize: 18),
          .foregroundColor: UIColor.white.withAlphaComponent(0.5)
        ]
        "PAGE \(index + 1)".draw(at: CGPoint(x: 700, y: 1140), withAttributes: pageNumAttrs)
      }

      let pageFileURL = comicDir.appendingPathComponent(pageName)
      try? pageData.write(to: pageFileURL)
    }

    // Save pages.json
    let pagesData = try? JSONEncoder().encode(pageNames)
    try? pagesData?.write(to: comicDir.appendingPathComponent("pages.json"))
    #elseif canImport(AppKit)
    let titlesMac = [
      ("THE COSMIC ODYSSEY", "Chapter 1: The Departure", NSColor(red: 0.1, green: 0.15, blue: 0.35, alpha: 1.0)),
      ("ORBITAL STATION AETHEL", "Systems Nominal • Warp Core Primed", NSColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1.0)),
      ("DEEP SPACE TRANSIT", "Entering Sector 9 • Sensors Detecting Anomaly", NSColor(red: 0.2, green: 0.1, blue: 0.35, alpha: 1.0)),
      ("FIRST CONTACT", "The Signal is Received • To Be Continued...", NSColor(red: 0.05, green: 0.25, blue: 0.3, alpha: 1.0))
    ]

    let size = NSSize(width: 800, height: 1200)
    for (index, pageName) in pageNames.enumerated() {
      let image = NSImage(size: size)
      image.lockFocus()
      let rect = NSRect(origin: .zero, size: size)
      let info = titlesMac[index]

      info.2.setFill()
      rect.fill()

      let panelRect = rect.insetBy(dx: 40, dy: 40)
      NSColor.white.withAlphaComponent(0.15).setFill()
      panelRect.fill()

      let border = NSBezierPath(rect: panelRect)
      NSColor.white.withAlphaComponent(0.6).setStroke()
      border.lineWidth = 4
      border.stroke()

      let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 36),
        .foregroundColor: NSColor.white
      ]
      info.0.draw(at: NSPoint(x: 64, y: 1060), withAttributes: titleAttrs)

      let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20),
        .foregroundColor: NSColor.cyan
      ]
      info.1.draw(at: NSPoint(x: 64, y: 1000), withAttributes: subAttrs)

      let pageNumAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 18),
        .foregroundColor: NSColor.white.withAlphaComponent(0.5)
      ]
      "PAGE \(index + 1)".draw(at: NSPoint(x: 680, y: 40), withAttributes: pageNumAttrs)

      image.unlockFocus()

      if let tiffData = image.tiffRepresentation,
         let bitmap = NSBitmapImageRep(data: tiffData),
         let pngData = bitmap.representation(using: .png, properties: [:]) {
        let pageFileURL = comicDir.appendingPathComponent(pageName)
        try? pngData.write(to: pageFileURL)
      }
    }

    let pagesData = try? JSONEncoder().encode(pageNames)
    try? pagesData?.write(to: comicDir.appendingPathComponent("pages.json"))
    #endif

    comicBook.addBookmark(Bookmark(pageOrLocation: 0, note: "Cover & Launch"))
    return comicBook
  }

  private func createSampleEPUB() -> Book {
    let epubID = UUID()
    let epubBook = Book(
      id: epubID,
      title: "Alice in Wonderland",
      author: "Lewis Carroll",
      coverImageName: "",
      content: "Alice falls down a rabbit hole into a fantasy realm populated by anthropomorphic creatures.",
      progress: 0.0,
      format: .epub
    )

    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return epubBook
    }
    let epubDir = docs.appendingPathComponent("Books").appendingPathComponent(epubID.uuidString)
    try? FileManager.default.createDirectory(at: epubDir, withIntermediateDirectories: true)

    let ch1Content = """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"/><title>Chapter 1</title>
    <style>body { font-family: -apple-system, serif; padding: 20px; line-height: 1.6; color: #f0f0f0; }</style>
    </head>
    <body>
    <h2>Chapter I: Down the Rabbit-Hole</h2>
    <p>Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought Alice "without pictures or conversations?"</p>
    <p>So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.</p>
    <p>There was nothing so VERY remarkable in that; nor did Alice think it so VERY much out of the way to hear the Rabbit say to itself, "Oh dear! Oh dear! I shall be late!"</p>
    </body>
    </html>
    """

    let ch2Content = """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"/><title>Chapter 2</title>
    <style>body { font-family: -apple-system, serif; padding: 20px; line-height: 1.6; color: #f0f0f0; }</style>
    </head>
    <body>
    <h2>Chapter II: The Pool of Tears</h2>
    <p>"Curiouser and curiouser!" cried Alice (she was so much surprised, that for the moment she quite forgot how to speak good English); "now I'm opening out like the largest telescope that ever was! Good-bye, feet!"</p>
    <p>And she began thinking over all the children she knew that were of the same age as herself, to see if she could have been changed for any of them.</p>
    <p>"I'm sure I'm not Ada," she said, "for her hair goes in such long ringlets, and mine doesn't go in ringlets at all; and I'm sure I can't be Mabel, for I know all sorts of things, and she, oh! she knows such a very little!"</p>
    </body>
    </html>
    """

    try? ch1Content.write(to: epubDir.appendingPathComponent("ch1.xhtml"), atomically: true, encoding: .utf8)
    try? ch2Content.write(to: epubDir.appendingPathComponent("ch2.xhtml"), atomically: true, encoding: .utf8)

    // Write spine.json
    let spine = ["ch1.xhtml", "ch2.xhtml"]
    let spineData = try? JSONEncoder().encode(spine)
    try? spineData?.write(to: epubDir.appendingPathComponent("spine.json"))

    // Write toc.json
    let toc = [
      Chapter(title: "Chapter I: Down the Rabbit-Hole", path: "ch1.xhtml"),
      Chapter(title: "Chapter II: The Pool of Tears", path: "ch2.xhtml")
    ]
    let tocData = try? JSONEncoder().encode(toc)
    try? tocData?.write(to: epubDir.appendingPathComponent("toc.json"))

    epubBook.url = epubDir
    epubBook.addBookmark(Bookmark(pageOrLocation: 0, note: "The Rabbit Hole Begins"))
    return epubBook
  }
}
