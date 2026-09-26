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
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

class BookService {
  static let shared = BookService()
  var modelContainer: ModelContainer?

  private init() {}

  @MainActor
  func setModelContainer(_ container: ModelContainer) {
    self.modelContainer = container
  }

  @MainActor
  func fetchAllBooks() -> [Book] {
    guard let context = modelContainer?.mainContext else { return [] }
    let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.lastReadDate, order: .reverse)])
    return (try? context.fetch(descriptor)) ?? []
  }

  @MainActor
  func fetchBook(id: UUID) -> Book? {
    guard let context = modelContainer?.mainContext else { return nil }
    let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
    return try? context.fetch(descriptor).first
  }

  @MainActor
  func fetchLatestBook() -> Book? {
    fetchAllBooks().first
  }

  // MARK: - CoreSpotlight Semantic Indexing (Apple Intelligence Search)
  func indexBookInSpotlight(_ book: Book) {
    #if canImport(CoreSpotlight)
    let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
    attributeSet.title = book.title
    attributeSet.creator = book.author
    attributeSet.contentDescription = "\(book.format?.displayName ?? "Book") by \(book.author)"
    
    // Rich semantic keywords and excerpt for Apple Intelligence Spotlight search
    var keywords = [book.title, book.author, book.format?.displayName ?? ""]
    if !book.content.isEmpty {
      let preview = String(book.content.prefix(300))
      attributeSet.textContent = preview
      let sampleWords = preview.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 4 }
      keywords.append(contentsOf: Set(sampleWords).prefix(15))
    }
    attributeSet.keywords = Array(Set(keywords))

    let item = CSSearchableItem(
      uniqueIdentifier: book.id.uuidString,
      domainIdentifier: "club.ironlattice.whisper.books",
      attributeSet: attributeSet
    )
    CSSearchableIndex.default().indexSearchableItems([item]) { error in
      if let error = error {
        print("Spotlight: Indexing warning: \(error.localizedDescription)")
      }
    }
    #endif
  }

  func deindexBookFromSpotlight(_ id: UUID) {
    #if canImport(CoreSpotlight)
    CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString]) { _ in }
    #endif
  }

  func seedBooks(context: ModelContext) {
    let books = generateRichSampleBooks()
    for book in books {
      context.insert(book)
      indexBookInSpotlight(book)
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
          ensureBookFilesExist(book: book)
          // Ensure existing books are indexed in Spotlight
          indexBookInSpotlight(book)
        }
        if didMigrate {
          try? context.save()
        }
      }
    } catch {
      print("Error checking for existing books: \(error)")
    }
  }

  func ensureBookFilesExist(book: Book) {
    guard let bookDir = book.bookDir else { return }
    let fileManager = FileManager.default
    if book.format == .epub {
      let ch1URL = bookDir.appendingPathComponent("chapter1.html")
      if !fileManager.fileExists(atPath: ch1URL.path) && (book.title.contains("Alice") || book.title.contains("Wonderland")) {
        populateAliceEPUB(at: bookDir)
      }
    } else if book.format == .comic {
      let ocrURL = bookDir.appendingPathComponent("ocr_transcript.txt")
      if !fileManager.fileExists(atPath: ocrURL.path) && (book.title.contains("Cosmic") || book.title.contains("Odyssey")) {
        populateComicFiles(at: bookDir)
      }
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

    "Can a cube that does not exist for any time at all, have a real existence?"
    """
  }

  private func createSamplePDF() -> URL? {
    let fileManager = FileManager.default
    guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }
    let pdfURL = docs.appendingPathComponent("WhisperUserGuide.pdf")

    if fileManager.fileExists(atPath: pdfURL.path) {
      return pdfURL
    }

    #if canImport(UIKit)
      let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)  // Standard US Letter
      let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

      let data = renderer.pdfData { context in
        // Page 1
        context.beginPage()
        let titleAttributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: 32, weight: .bold),
          .foregroundColor: UIColor.label,
        ]
        let title = "Whisper"
        title.draw(at: CGPoint(x: 50, y: 80), withAttributes: titleAttributes)

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: 18, weight: .medium),
          .foregroundColor: UIColor.secondaryLabel,
        ]
        let subtitle = "Liquid Glass Digital Reader — User Guide"
        subtitle.draw(at: CGPoint(x: 50, y: 125), withAttributes: subtitleAttributes)

        let bodyAttributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: 14, weight: .regular),
          .foregroundColor: UIColor.label,
        ]
        let body1 = """
          Welcome to Whisper, an immersive reading environment designed with Apple's premium \\
          Liquid Glass visual hierarchy. Whisper redefines document navigation through tactile, \\
          fluid gestures and adaptive ambient aesthetics.

          Key Features:
          • Multi-Format Support: Seamlessly read EPUB, PDF, CBZ/CBR comics, and plain text.
          • Liquid Glass UI: Dynamic background mesh adapts smoothly to your content.
          • Continuous & Paginated Modes: Switch effortlessly between standard vertical scrolling \\
          and horizontal column pagination.
          • Tactile Gesture Controls: Pinch-to-zoom, swipe-to-turn, and responsive touch controls.
          • Smart Bookmarking: Save your favorite quotes and notes with persistent memory.
          """
        let rect1 = CGRect(x: 50, y: 170, width: 512, height: 500)
        body1.draw(in: rect1, withAttributes: bodyAttributes)

        // Page 2
        context.beginPage()
        let page2Title = "Gesture Navigation & Controls"
        page2Title.draw(at: CGPoint(x: 50, y: 80), withAttributes: titleAttributes)

        let body2 = """
          Whisper is built from the ground up for fluid, natural interaction:

          • Tap center screen: Toggle reading controls, table of contents, and appearance settings.
          • Swipe left/right: Turn pages in paginated mode.
          • Smooth scroll: Enjoy 120Hz ProMotion inertial scrolling in continuous scroll mode.
          • Pinch gesture: Dynamically scale text or zoom into detailed comic artwork.
          • Long-press: Access contextual actions, text selection, and Apple Intelligence Writing Tools.

          Enjoy your reading journey with Whisper.
          """
        let rect2 = CGRect(x: 50, y: 140, width: 512, height: 500)
        body2.draw(in: rect2, withAttributes: bodyAttributes)
      }

      try? data.write(to: pdfURL)
      return pdfURL

    #elseif canImport(AppKit)
      let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
      let pdfData = NSMutableData()
      guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
      var mediaBox = pageRect
      guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        return nil
      }

      // Page 1
      context.beginPage(mediaBox: &mediaBox)
      let gc1 = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.current = gc1

      let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.labelColor,
      ]
      let p1Title = NSAttributedString(string: "Whisper", attributes: titleAttrs)
      p1Title.draw(at: CGPoint(x: 50, y: 680))

      let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
      let p1Sub = NSAttributedString(
        string: "Liquid Glass Digital Reader — User Guide", attributes: subAttrs)
      p1Sub.draw(at: CGPoint(x: 50, y: 645))

      let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.labelColor,
      ]
      let p1Body = NSAttributedString(
        string:
          "Welcome to Whisper, an immersive reading environment designed with Apple's premium Liquid Glass visual hierarchy. Whisper supports EPUB, PDF, CBZ/CBR comics, and plain text with continuous touch scrolling, typography customization, and bookmarking.",
        attributes: bodyAttrs)
      p1Body.draw(in: CGRect(x: 50, y: 400, width: 512, height: 220))

      context.endPage()

      // Page 2
      context.beginPage(mediaBox: &mediaBox)
      let gc2 = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.current = gc2

      let p2Title = NSAttributedString(
        string: "Gesture Navigation & Controls", attributes: titleAttrs)
      p2Title.draw(at: CGPoint(x: 50, y: 680))

      let p2Body = NSAttributedString(
        string:
          "Whisper is built from the ground up for fluid, natural interaction. Tap the center of the screen to reveal HUD controls, swipe or click chevrons to flip pages, and use smooth inertia scrolling for continuous reading.",
        attributes: bodyAttrs)
      p2Body.draw(in: CGRect(x: 50, y: 450, width: 512, height: 200))

      context.endPage()
      context.closePDF()

      try? (pdfData as Data).write(to: pdfURL)
      return pdfURL
    #endif
  }

  func populateComicFiles(at comicDir: URL) {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: comicDir, withIntermediateDirectories: true)

    let comicInfoXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <Title>The Cosmic Odyssey</Title>
      <Series>The Cosmic Odyssey</Series>
      <Number>1</Number>
      <Summary>Commander Valen leads the exploratory vessel Prometheus into the uncharted Orion Nebula. When the starship encounters a temporal rift emitting structured radio pulses, Lieutenant Kira and Dr. Aris discover an ancient alien artifact dormant for three million years.</Summary>
      <Writer>Nova Stellaris</Writer>
      <Penciller>Aria Vance</Penciller>
      <Characters>Commander Valen, Lieutenant Kira, Dr. Aris, Prometheus AI</Characters>
      <Genre>Sci-Fi Adventure</Genre>
    </ComicInfo>
    """
    let xmlURL = comicDir.appendingPathComponent("ComicInfo.xml")
    if !fileManager.fileExists(atPath: xmlURL.path) {
      try? comicInfoXML.write(to: xmlURL, atomically: true, encoding: .utf8)
    }

    let ocrTranscript = """
    [Metadata]
    Title: The Cosmic Odyssey
    Series: The Cosmic Odyssey #1
    Writer: Nova Stellaris
    Characters: Commander Valen, Lieutenant Kira, Dr. Aris, Prometheus AI
    Summary: Commander Valen leads the exploratory vessel Prometheus into the uncharted Orion Nebula. When the starship encounters a temporal rift emitting structured radio pulses, Lieutenant Kira and Dr. Aris discover an ancient alien artifact dormant for three million years.

    [Page 1]
    THE COSMIC ODYSSEY
    Chapter 1: Departure from Sector 7
    Commander Valen: "All systems online. The hyperdrive core is fully charged. Set course for the Orion Nebula."
    Lieutenant Kira: "Coordinates locked, Commander. Sub-space sensors are detecting a strange rhythmic pulse ahead."
    Dr. Aris: "It is not a pulsar. The pulse pattern is mathematical."

    [Page 2]
    Chapter 2: The Temporal Rift
    Lieutenant Kira: "Warning! Massive gravitational anomaly pulling the Prometheus off course!"
    Commander Valen: "Hold steady! Divert all auxiliary power to inertial dampeners!"
    Dr. Aris: "Look at the visual telemetry! Space is folding around us!"
    Prometheus AI: "Spatial stability at 42 percent. Approaching singularity threshold."

    [Page 3]
    Chapter 3: The Ancient Beacon
    Prometheus AI: "Sensors clear. Temporal rift bypassed. Massive artificial structure detected ahead."
    Commander Valen: "Magnify the main screen. By the stars... what is that?"
    Lieutenant Kira: "It is an alien monolith. And the beacon has just awakened."
    Dr. Aris: "After three million years, it has been waiting for someone to find it."
    """
    let ocrURL = comicDir.appendingPathComponent("ocr_transcript.txt")
    if !fileManager.fileExists(atPath: ocrURL.path) {
      try? ocrTranscript.write(to: ocrURL, atomically: true, encoding: .utf8)
    }

    let pages = ["comic_page_1.jpg", "comic_page_2.jpg", "comic_page_3.jpg"]
    let pagesURL = comicDir.appendingPathComponent("pages.json")
    if !fileManager.fileExists(atPath: pagesURL.path) {
      if let data = try? JSONEncoder().encode(pages) {
        try? data.write(to: pagesURL)
      }
    }
  }

  private func createSampleComic() -> Book {
    let bookID = UUID()
    let comicDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Books")
      .appendingPathComponent(bookID.uuidString)

    try? FileManager.default.createDirectory(at: comicDir, withIntermediateDirectories: true)

    let pageNames = ["Page 1 - Departure", "Page 2 - Hyperdrive", "Page 3 - Discovery"]
    var imageFilenames: [String] = []

    for (index, title) in pageNames.enumerated() {
      let filename = "comic_page_\(index + 1).jpg"
      let fileURL = comicDir.appendingPathComponent(filename)

      #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200))
        let img = renderer.image { ctx in
          let colors: [UIColor] = [
            UIColor(red: 0.08, green: 0.05, blue: 0.18, alpha: 1.0),
            UIColor(red: 0.15, green: 0.10, blue: 0.35, alpha: 1.0),
            UIColor(red: 0.05, green: 0.12, blue: 0.25, alpha: 1.0),
          ]
          let bg = colors[index % colors.count]
          bg.setFill()
          ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1200))

          let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
            .foregroundColor: UIColor.white,
          ]
          let str = "THE COSMIC ODYSSEY"
          str.draw(at: CGPoint(x: 60, y: 100), withAttributes: textAttrs)

          let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: UIColor.cyan,
          ]
          title.draw(at: CGPoint(x: 60, y: 160), withAttributes: subAttrs)
        }
        if let data = img.jpegData(compressionQuality: 0.85) {
          try? data.write(to: fileURL)
          imageFilenames.append(filename)
        }
      #elseif canImport(AppKit)
        let img = NSImage(size: NSSize(width: 800, height: 1200))
        img.lockFocus()
        let colors = [
          NSColor(calibratedRed: 0.08, green: 0.05, blue: 0.18, alpha: 1.0),
          NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.35, alpha: 1.0),
          NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.25, alpha: 1.0),
        ]
        colors[index % colors.count].setFill()
        NSRect(x: 0, y: 0, width: 800, height: 1200).fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
          .font: NSFont.systemFont(ofSize: 42, weight: .heavy),
          .foregroundColor: NSColor.white,
        ]
        let titleStr = NSAttributedString(string: "THE COSMIC ODYSSEY", attributes: titleAttrs)
        titleStr.draw(at: NSPoint(x: 60, y: 1050))

        let subAttrs: [NSAttributedString.Key: Any] = [
          .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
          .foregroundColor: NSColor.cyan,
        ]
        let subStr = NSAttributedString(string: title, attributes: subAttrs)
        subStr.draw(at: NSPoint(x: 60, y: 990))

        img.unlockFocus()

        if let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .jpeg, properties: [:])
        {
          try? data.write(to: fileURL)
          imageFilenames.append(filename)
        }
      #endif
    }

    populateComicFiles(at: comicDir)

    return Book(
      id: bookID,
      title: "The Cosmic Odyssey",
      author: "Nova Stellaris",
      coverImageName: "",
      content: "Commander Valen leads the exploratory vessel Prometheus into the uncharted Orion Nebula. When the starship encounters a temporal rift emitting structured radio pulses, Lieutenant Kira and Dr. Aris discover an ancient alien artifact dormant for three million years.",
      progress: 0.0,
      format: .comic,
      url: comicDir,
      sampleImages: imageFilenames
    )
  }

  func populateAliceEPUB(at epubDir: URL) {
    try? FileManager.default.createDirectory(at: epubDir, withIntermediateDirectories: true)

    let ch1 = """
      <!DOCTYPE html>
      <html>
      <head><title>Chapter 1: Down the Rabbit-Hole</title><meta charset="utf-8"></head>
      <body>
        <h1>Alice's Adventures in Wonderland</h1>
        <h2>Chapter I: Down the Rabbit-Hole</h2>
        <p>Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought Alice "without pictures or conversations?"</p>
        <p>So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.</p>
        <p>There was nothing so <i>very</i> remarkable in that; nor did Alice think it so <i>very</i> much out of the way to hear the Rabbit say to itself, "Oh dear! Oh dear! I shall be late!" (when she thought it over afterwards, it occurred to her that she ought to have wondered at this, but at the time it all seemed quite natural); but when the Rabbit actually <i>took a watch out of its waistcoat-pocket</i>, and looked at it, and then hurried on, Alice started to her feet, for it flashed across her mind that she had never before seen a rabbit with either a waistcoat-pocket, or a watch to take out of it, and burning with curiosity, she ran across the field after it, and fortunately was just in time to see it pop down a large rabbit-hole under the hedge.</p>
        <p>In another moment down went Alice after it, never once considering in the world how in the world she was to get out again.</p>
      </body>
      </html>
      """

    let ch2 = """
      <!DOCTYPE html>
      <html>
      <head><title>Chapter 2: The Pool of Tears</title><meta charset="utf-8"></head>
      <body>
        <h1>Alice's Adventures in Wonderland</h1>
        <h2>Chapter II: The Pool of Tears</h2>
        <p>"Curiouser and curiouser!" cried Alice (she was so much surprised, that for the moment she quite forgot how to speak good English); "now I'm opening out like the largest telescope that ever was! Good-bye, feet!" (for when she looked down at her feet, they seemed to be almost out of sight, they were getting so far off).</p>
        <p>"Oh, my poor little feet, I wonder who will put on your shoes and stockings for you now, dears? I'm sure <i>I</i> shan't be able! I shall be a great deal too far off to trouble myself about you: you must manage the best way you can;—but I must be kind to them," thought Alice, "or perhaps they won't walk the way I want to go! Let me see: I'll give them a new pair of boots every Christmas."</p>
        <p>And she went on planning to herself how she would manage it. "They must go by the carrier," she thought; "and how funny it'll seem, sending presents to one's own feet! And how odd the directions will look!"</p>
      </body>
      </html>
      """

    let ch1URL = epubDir.appendingPathComponent("chapter1.html")
    let ch2URL = epubDir.appendingPathComponent("chapter2.html")

    try? ch1.write(to: ch1URL, atomically: true, encoding: .utf8)
    try? ch2.write(to: ch2URL, atomically: true, encoding: .utf8)

    // Save spine.json
    let spine = ["chapter1.html", "chapter2.html"]
    if let data = try? JSONEncoder().encode(spine) {
      try? data.write(to: epubDir.appendingPathComponent("spine.json"))
    }

    // Save toc.json
    let toc = [
      Chapter(title: "Chapter I: Down the Rabbit-Hole", path: "chapter1.html"),
      Chapter(title: "Chapter II: The Pool of Tears", path: "chapter2.html"),
    ]
    if let data = try? JSONEncoder().encode(toc) {
      try? data.write(to: epubDir.appendingPathComponent("toc.json"))
    }
  }

  private func createSampleEPUB() -> Book {
    let bookID = UUID()
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let epubDir = docs.appendingPathComponent("Books").appendingPathComponent(bookID.uuidString)

    populateAliceEPUB(at: epubDir)

    return Book(
      id: bookID,
      title: "Alice's Adventures in Wonderland",
      author: "Lewis Carroll",
      coverImageName: "",
      content: "The timeless fantasy classic of Alice falling down the rabbit hole.",
      progress: 0.0,
      format: .epub,
      url: epubDir
    )
  }
}
